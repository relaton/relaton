require "date"
require "json"
require "mechanize"
require "relaton/core"
require "relaton/index"
require_relative "../etsi"
require_relative "data_parser"

module Relaton
  module Etsi
    class DataFetcher < Core::DataFetcher
      PAGE_SIZE = 50

      # `version=1` keeps the superseded EDITIONS of a document in the result
      # set; `version=0` returns only the current edition of each branch. The
      # status flags below are a separate axis and already permissive, so this
      # is what makes e.g. all three editions of `ETSI EN 319 142-1` retrievable
      # instead of one. It also makes the crawl about 2.4 times larger — see
      # lib/relaton/etsi/CLAUDE.md before changing it back.
      SOURCEURL = "https://www.etsi.org/custom/standardssearch/data.php?format=json&includeScope=1&" \
        "page=%<page>s&search=&title=1&etsiNumber=1&content=1&version=1&onApproval=1&published=1&" \
        "withdrawn=1&historical=1&isCurrent=1&superseded=1&startDate=1988-01-15&endDate=%<date>s&" \
        "harmonized=0&keyword=&TB=&stdType=&frequency=&mandate=&collection=&sort=1&x=%<timestamp>s".freeze

      def index
        @index ||= Relaton::Index.find_or_create(
          :etsi, file: "#{INDEXFILE}.yaml", pubid_class: ::Pubid::Etsi::Identifier
        )
      end

      def log_error(msg)
        Util.error msg
      end

      #
      # Fetch all ETSI documents from the ETSI website.
      #
      # @param [Object] _source unused, required by superclass interface
      #
      def fetch(_source = nil)
        first_page = fetch_page(1)
        process_records(first_page)
        fetch_remaining_pages(first_page)
        index.save
        report_errors
      end

      #
      # Fetch pages 2..N. A page that stays bad after its retries is fetched
      # again after the last page; if it is still bad, the crawl fails. A page
      # is never skipped: relaton-data-etsi deletes data/ before the crawl and
      # commits what it writes, so a skipped page would unpublish its documents.
      #
      # N comes from page 1's total_count, but the result set is sorted by
      # deliverable number, so a document published during the crawl shifts the
      # later pages by one. The crawl therefore reads on past N while the pages
      # stay full (at most MAX_EXTRA_PAGES), and one page past a deferred last
      # page; a record read twice overwrites its own file.
      #
      def fetch_remaining_pages(first_page) # rubocop:disable Metrics/MethodLength
        total_pages = last = last_page(first_page)
        deferred = []
        page = 2
        while page <= last
          check_extra_pages page, total_pages
          size = fetch_next_page(page, deferred)
          break if size&.zero?

          last = page + 1 if page == last && read_on?(size, page, total_pages)
          page += 1
        end
        fetch_deferred_pages(deferred, total_pages)
      end

      def last_page(first_page)
        total = first_page.first ? first_page.first["total_count"].to_i : 0
        last = (total / PAGE_SIZE.to_f).ceil
        first_page.size >= PAGE_SIZE ? [last, 2].max : last
      end

      #
      # Whether to read the page after the last one: after a full page, or
      # after a deferred page inside the total_count range. A deferred page
      # past that range does not extend it, so a server that answers bad
      # bodies past the end cannot keep the crawl going.
      #
      def read_on?(size, page, total_pages)
        size ? size >= PAGE_SIZE : page <= total_pages
      end

      def check_extra_pages(page, total_pages)
        return if page <= total_pages + MAX_EXTRA_PAGES

        raise BadPage, "ETSI page #{page} is still full #{MAX_EXTRA_PAGES} " \
                       "pages past total_count (#{total_pages} pages)."
      end

      #
      # @return [Integer, nil] the number of records on the page; nil for a
      #   deferred page
      #
      def fetch_next_page(page, deferred)
        records = fetch_page(page)
        process_records(records)
        records.size
      rescue BadPage => e
        Util.warn "#{e.message} Fetching it again after the last page."
        deferred << page
        nil
      end

      def fetch_deferred_pages(pages, total_pages)
        return if pages.empty?

        sleep DEFERRED_DELAY
        failed = pages.filter_map do |page|
          refetch_page page, total_pages
        rescue BadPage => e
          e.message
        end
        raise BadPage, failed.join(" ") if failed.any?
      end

      # @return [String, nil] the failure message, nil on success
      def refetch_page(page, total_pages)
        records = fetch_page(page)
        if records.empty? && page <= total_pages
          return "ETSI page #{page} is empty on the re-fetch."
        end

        process_records records
        nil
      end

      def fetch_page(page)
        date = Time.now.to_date + 1
        timestamp = (Time.now.to_f * 1000).to_i
        url = format(SOURCEURL, page: page, date: date, timestamp: timestamp)
        fetch_with_retry(url) { |body| parse_page(page, body) }
      end

      #
      # ETSI's data.php sometimes answers with PHP's `Array` text in place of
      # JSON (relaton-data-etsi crawl 36761804954); a re-fetch gets JSON.
      #
      # @raise [BadPage] when the body is not a JSON array
      #
      def parse_page(page, body)
        records = JSON.parse(body)
        return records if records.is_a?(Array)

        raise BadPage, bad_page_message(page, body)
      rescue JSON::ParserError
        raise BadPage, bad_page_message(page, body)
      end

      def bad_page_message(page, body)
        "ETSI page #{page} is not a JSON array: #{body.to_s[0, 200].inspect}."
      end

      def process_records(records)
        records.each do |record|
          save DataParser.new(normalize(record), @errors).parse
        end
      end

      def normalize(record)
        {
          "ETSI deliverable" => record["ETSI_DELIVERABLE"],
          "title" => record["TITLE"],
          "Details link" => "https://webapp.etsi.org/workprogram/Report_WorkItem.asp?WKI_ID=#{record['wki_id']}",
          "PDF link" => "https://www.etsi.org/deliver/#{record['EDSpathname']}#{record['EDSPDFfilename']}",
          "Status" => derive_status(record),
          "Keywords" => record["Keywords"].to_s,
          "Technical body" => record["TB"],
          "Scope" => record["Scope"],
        }
      end

      def derive_status(record)
        return "Withdrawn" if record["ACTION_TYPE"] == "WD"

        code = record["STATUS_CODE"].to_i
        return "On Approval" if code < 12
        return "Historical" if code == 13

        "Published"
      end

      # A page body that is not a JSON array. See #parse_page.
      class BadPage < StandardError; end

      # Seconds to wait before a bad page is fetched again after the last page.
      DEFERRED_DELAY = 60

      # Full pages read past page 1's total_count before the crawl fails.
      MAX_EXTRA_PAGES = 10

      NETWORK_ERRORS = [
        Mechanize::Error, Net::OpenTimeout, Net::ReadTimeout,
        SocketError, Errno::ECONNRESET
      ].freeze

      #
      # @yield [String] the body; the block's result is returned, and a BadPage
      #   it raises is retried like a network error
      #
      def fetch_with_retry(url, retries: 3, delay: 2) # rubocop:disable Metrics/MethodLength
        attempt = 0
        begin
          body = Mechanize.new.get(url).body
          block_given? ? yield(body) : body
        rescue *NETWORK_ERRORS, BadPage => e
          attempt += 1
          if attempt <= retries
            Util.info "Fetch failed (#{e.message}), " \
                      "retrying (#{attempt}/#{retries})..."
            sleep delay * attempt
            retry
          end
          raise
        end
      end

      def save(bib)
        id = bib.docidentifier.first.content
        pid = pubid(id) or return # skip ids pubid can't parse/serialize

        # Distinct docids can sanitize to one filename (`output_file` collapses
        # `/`, `-`, `.`, `:` and `()` alike, and ETSI ids use all of them), which
        # used to overwrite silently. Take a path of our own. There is no @files
        # here, so a repeat of the SAME id still resolves to one path and
        # overwrites itself, as before.
        file = unique_output_file id
        if file != output_file(id)
          Util.warn "File #{output_file id} already exists. Docid: #{id}. Writing #{file} instead."
        end
        File.write file, serialize(bib), encoding: "UTF-8"
        index.add_or_update pid, file
      end

      #
      # Parse an ETSI docid into a Pubid::Etsi identifier, or nil when it can't
      # be parsed or serialized. Storing the pubid object (not its hash) lets
      # Relaton::Index sort the index by id number and serialize each id to its
      # `_type: pubid:etsi:*` hash on save. A single unindexable id must never
      # abort the crawl or corrupt the index, so it is skipped defensively
      # (mirrors Relaton::Nist#pubid / Relaton::Jcgm#add_to_index). ETSI's whole
      # published corpus parses on the pinned pubid; the guard protects against a
      # future malformed record.
      #
      # @param [String] id docidentifier content, e.g. "ETSI GS ZSM 012 V1.1.1 (2022-12)"
      # @return [::Pubid::Etsi::Identifier, nil]
      #
      def pubid(id)
        pid = ::Pubid::Etsi.parse id
        pid.to_hash # skip ids whose to_hash raises so index.save can't fail
        pid
      rescue StandardError
        nil
      end

      def to_yaml(bib)
        bib.to_yaml
      end

      def to_xml(bib)
        bib.to_xml bibdata: true
      end

      def to_bibxml(bib)
        bib.to_rfcxml
      end
    end
  end
end
