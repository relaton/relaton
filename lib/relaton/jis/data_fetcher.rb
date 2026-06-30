# frozen_string_literal: true

require_relative "../jis"
require_relative "scraper"

module Relaton
  module Jis
    class DataFetcher < Core::DataFetcher
      URL = "https://webdesk.jsa.or.jp/books/"

      def initialize(output, format)
        super
        @queue = SizedQueue.new 10
        @threads = create_thread_pool 5
        @mutex = Mutex.new
      end

      def log_error(msg)
        Util.error msg
      end

      def index
        @index ||= Relaton::Index.find_or_create :jis, file: "#{INDEXFILE}.yaml"
      end

      # Pubid-based index built in parallel with the legacy string index. The
      # pool keys by type, so requesting a second :jis index with a different
      # file evicts the v1 Type from the pool, but we keep our own reference in
      # @index, so both stay live for the duration of the crawl.
      def index_v2
        @index_v2 ||= Relaton::Index.find_or_create(
          :jis, file: "#{INDEXFILE_V2}.yaml", pubid_class: ::Pubid::Jis::Identifier
        )
      end

      # Parse a primary docidentifier string into a pubid identifier; nil (with
      # a warning) if pubid can't parse it, so a single bad id never aborts the
      # crawl or corrupts index-v2.
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

      def fetch(_source = nil)
        return unless initial_post

        resp = agent.get "#{URL}W11M0070/index"
        parse_page resp
        index.save
        index_v2.save
        report_errors
      end

      def initial_post
        return true if @initial_time && Time.now - @initial_time < 600

        body = { record: 0, dantai: "JIS", searchtype2: 1,
                 status_1: 1, status_2: 2 } # rubocop:disable Naming/VariableNumber
        resp = agent.post "#{URL}W11M0270/index", body
        disp = JSON.parse resp.body
        @initial_time = Time.now
        disp["status"] || Util.warn("No results found for JIS")
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
        end_threads_and_wait
      end

      def parse_offset(resp) # rubocop:disable Metrics/AbcSize
        if resp.at('//*[@id="btnPaging"]') # first page
          xpath = '//script[contains(.,"var count =")]'
          @count = resp.at(xpath).text.match(/var count = (\d+);/)[1]
          resp.at("//*[@id='offset']")[:value].to_i
        else
          script = resp.at("//script").text
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
        file = output_file id
        @mutex.synchronize do
          if @files.include?(file)
            Util.warn "File #{file} already exists. Duplication URL: #{url}"
          else
            @files << file
            File.write file, serialize(bib), encoding: "UTF-8"
            index.add_or_update id, file
            pid = pubid id
            index_v2.add_or_update pid, file if pid
          end
        end
      end
    end
  end
end
