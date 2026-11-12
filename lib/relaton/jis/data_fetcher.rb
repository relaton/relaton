# frozen_string_literal: true


require_relative "../jis"
require_relative "scraper"

module Relaton
  module Jis
    class DataFetcher < Core::DataFetcher
      URL = "https://webdesk.jsa.or.jp/books/"

      # The Webdesk lists a crawl reads, in this order: the JIS search, then
      # the JWES group list (WES standards, relaton-jis#18). Webdesk keeps the
      # open list in the session, and the list page and its paging
      # (`W11M0070`) read that list. So the lists are read one after the
      # other, and a session refresh opens the current list again.
      LISTS = %w[JIS JWES].freeze

      def initialize(output, format)
        super
        @queue = SizedQueue.new 10
        @threads = create_thread_pool 5
        @mutex = Mutex.new
      end

      def log_error(msg)
        Util.error msg
      end

      # The pubid index-v2, the only index a crawl writes. relaton-data-jis
      # rebuilds the legacy string index-v1 from data/ in its own crawler.
      def index
        @index ||= Relaton::Index.find_or_create(
          :jis, file: "#{INDEXFILE}.yaml", pubid_class: ::Pubid::Jis::Identifier
        )
      end

      # Parse a primary docidentifier string into a pubid identifier; nil (with
      # a warning) if pubid can't parse it, so a single bad id never aborts the
      # crawl or corrupts the index.
      def pubid(id)
        ::Pubid::Jis::Identifier.parse id
      rescue StandardError => e
        Util.warn "Failed to parse `#{id}` with pubid: #{e.message}"
        nil
      end

      def to_yaml(bib)
        Item.to_yaml bib
      end

      def to_xml(bib)
        Bibdata.to_xml bib
      end

      def to_bibxml(bib)
        bib.to_rfcxml
      end

      def create_thread_pool(size)
        Array.new(size) do
          Thread.new do
            until (url = @queue.shift) == :END
              fetch_doc url
            end
          end
        end
      end

      def fetch_doc(url) # rubocop:disable Metrics/MethodLength
        attempts = 0
        begin
          bib = Scraper.new(url, @errors).fetch
        rescue StandardError => e
          attempts += 1
          if attempts < 5
            sleep 2
            retry
          else
            Util.warn "URL: #{url}"
            Util.warn "#{e.message}\n#{e.backtrace[0..6].join("\n")}"
          end
        else
          save_doc bib, url
        end
      end

      # relaton-data-jis deletes data/ before a crawl and publishes what the
      # crawl wrote. A list that does not open raises, so the crawl job fails
      # and does not publish a corpus without that list.
      def fetch(_source = nil)
        failed = begin
          LISTS.find { |list| !fetch_list(list) }
        ensure
          end_threads_and_wait
        end
        raise Error, "Webdesk list #{failed} did not open" if failed

        index.save
        report_errors
      end

      # Queue every document of one list. False if the list does not open.
      def fetch_list(list)
        @list = list
        @initial_time = nil
        return false unless initial_post

        parse_page agent.get("#{URL}W11M0070/index")
        true
      end

      # Open the current list in the session, unless it was opened less than
      # 10 minutes ago.
      def initial_post
        return true if @initial_time && Time.now - @initial_time < 600

        status = @list == "JWES" ? open_group_list(@list) : open_jis_search
        @initial_time = Time.now
        status || Util.warn("No results found for #{@list}")
      end

      def open_jis_search
        body = { record: 0, dantai: "JIS", searchtype2: 1,
                 status_1: 1, status_2: 2 } # rubocop:disable Naming/VariableNumber
        resp = agent.post "#{URL}W11M0270/index", body
        Relaton::Json.parse_external(resp.body)["status"]
      end

      # A group list from the "domestic group publications" page. The link
      # redirects to the list page, which states the count of documents.
      def open_group_list(dantai)
        page = agent.get "#{URL}W11S0260/getSearchAllListByLink" \
                         "?dantai_cd=#{dantai}&display=KOKUNAI"
        script = page.at_xpath('//script[contains(.,"var count =")]')
        script&.text.to_s[/var count = (\d+);/, 1].to_i.positive?
      end

      def agent
        @agent ||= Mechanize.new
      end

      def parse_page(resp)
        while resp
          xpath = '//div[@class="blockGenaral"]/a'
          resp.xpath(xpath).each { |a| @queue << a[:href] }
          offset = parse_offset resp
          break if offset >= count

          resp = get_next_page(offset)
        end
      end

      def parse_offset(resp) # rubocop:disable Metrics/AbcSize
        if resp.at_xpath('//*[@id="btnPaging"]') # first page
          xpath = '//script[contains(.,"var count =")]'
          @count = resp.at_xpath(xpath).text.match(/var count = (\d+);/)[1]
          resp.at_xpath("//*[@id='offset']")[:value].to_i
        else
          script = resp.at_xpath("//script").text
          script.match(/\("offset"\)\.value = '(\d+)'/)[1].to_i
        end
      end

      def end_threads_and_wait
        @threads.size.times { @queue << :END }
        @queue.close
        @threads.each(&:join)
      end

      def count
        @count.to_i
      end

      def get_next_page(offset) # rubocop:disable Metrics/MethodLength
        attempts = 0
        begin
          if initial_post
            url = "#{URL}W11M0070/getAddList"
            agent.post url, search_type: "JIS", offset: offset
          end
        rescue StandardError => e
          attempts += 1
          if attempts < 5
            sleep 2
            retry
          else
            Util.warn "#{e.message}\n#{e.backtrace[0..6].join("\n")}"
          end
        end
      end

      def save_doc(bib, url) # rubocop:disable Metrics/MethodLength
        return unless bib

        id = bib.docidentifier.find(&:primary).content
        @mutex.synchronize do
          # Two distinct ids can sanitize to one filename, in which case the
          # second document used to be dropped. Give it a path of its own; a
          # genuine duplicate (same id) still resolves to one path and is still
          # skipped. Inside the lock: unique_output_file reserves state.
          file = unique_output_file id
          # A reserved path only ever belongs to one id, so a hit here is the
          # same document again. Checked FIRST: a disambiguated path stays !=
          # output_file forever, so gating this on that comparison would make a
          # repeat of a disambiguated id skip the skip and overwrite itself.
          if @files.include?(file)
            Util.warn "File #{file} already exists. Duplication URL: #{url}"
            next
          end

          Util.warn "File #{output_file id} already exists; writing #{file} instead" if file != output_file(id)
          @files << file
          File.write file, serialize(bib), encoding: "UTF-8"
          pid = pubid id
          index.add_or_update pid, file if pid
        end
      end
    end
  end
end
