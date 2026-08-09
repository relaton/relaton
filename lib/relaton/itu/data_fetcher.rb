require "net/http"
require "json"
require "uri"
require "mechanize"
require_relative "../itu"
require_relative "data_parser_r"
require_relative "data_parser_t"

module Relaton
  module Itu
    class DataFetcher < Core::DataFetcher
      SEARCH_URL = "https://www.itu.int/net4/ITU-T/search/GlobalSearch/RunSearch".freeze
      # ITU-T recommendation index (issue relaton-itu#80). main_edition_flag=0
      # returns one row per edition, including supplements; a single request
      # enumerates the whole ITU-T corpus.
      SEARCH_RECS_URL = "https://www.itu.int/mws/api/recommendations/searchRecs".freeze
      # A browser User-Agent — www.itu.int sits behind an F5 WAF that rejects
      # non-browser clients (it is what killed the old RunSearch endpoint), so
      # Net::HTTP's default "Ruby" UA must not be sent.
      USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " \
                   "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Safari/605.1.15".freeze
      ROWS = 100
      MAX_EMPTY_PAGES = 3

      def index
        @index ||= Relaton::Index.find_or_create(
          :itu, file: "#{INDEXFILE}.yaml", pubid_class: ::Pubid::Itu::Identifier
        )
      end

      def log_error(msg)
        Util.error msg
      end

      # @param source [String, nil] "itu-t" harvests ITU-T recommendations via
      #   the searchRecs index (issue #80); "itu-r" (and nil, legacy) harvests
      #   ITU-R publications via the RunSearch endpoint.
      def fetch(source = nil)
        source == "itu-t" ? fetch_recommendations : fetch_publications
        index.save
        report_errors
      end

      # ITU-T harvester: one searchRecs request enumerates every edition and
      # supplement; each row is then enriched with getRecHdrDetail-sourced fields
      # (abstract, ISO co-id, editorial-group contributors, status) via a shared
      # browser-UA agent, so harvested records match the live runtime output.
      # This is ~one getRecHdrDetail (+ one rec.aspx for the workgroup) per
      # record — the bulk of the crawl's cost — so progress is logged.
      def fetch_recommendations
        agent = rec_agent
        rows = search_recs
        rows.each_with_index do |row, i|
          bib = DataParserT.parse(row, agent, @errors)
          write_file(bib) if bib
          Util.info "ITU-T: enriched #{i + 1}/#{rows.size}" if ((i + 1) % 500).zero?
        rescue => e # rubocop:disable Style/RescueStandardError
          Util.error "#{e.message}\n#{e.backtrace}"
        end
      end

      # Mechanize agent for per-record enrichment. A browser User-Agent is
      # required — www.itu.int sits behind the F5 WAF that rejects non-browser
      # clients (mirrors HitCollection#agent).
      def rec_agent
        Mechanize.new.tap { |a| a.user_agent_alias = "Mac Safari" }
      end

      # ITU-R harvester (legacy RunSearch pagination).
      def fetch_publications
        start = 0
        empty_pages = 0
        loop do
          results = search_request(start)
          if results.empty?
            empty_pages += 1
            break if empty_pages >= MAX_EMPTY_PAGES

            start += ROWS
            next
          end

          empty_pages = 0
          results.each do |result|
            bib = DataParserR.parse(result, @errors)
            write_file(bib) if bib
          rescue => e # rubocop:disable Style/RescueStandardError
            Util.error "#{e.message}\n#{e.backtrace}"
          end

          start += ROWS
        end
      end

      # @param bib [Relaton::Itu::ItemData]
      def write_file(bib) # rubocop:disable Metrics/AbcSize
        id = bib.docidentifier.find(&:primary).content
        file = output_file(id)
        if @files.include? file
          Util.warn "File #{file} exists."
        else
          @files << file
        end
        index_primary(id, file)
        File.write file, serialize(bib), encoding: "UTF-8"
      end

      # Index the id's parsed pubid. If it can't be parsed/round-tripped, record
      # it so #report_errors raises a tracked GitHub issue; the data file is
      # still written, so the document is not lost — only unindexed until its id
      # parses (mirrors Relaton::Iso::DataFetcher#index_primary).
      #
      # @param id [String] primary docidentifier content, e.g. "ITU-R BO.600-1"
      # @param file [String] file name of the document
      def index_primary(id, file)
        if (pid = pubid(id))
          index.add_or_update pid, file
        else
          unparseable_ids << [id, file]
        end
      end

      def unparseable_ids
        @unparseable_ids ||= []
      end

      # Surface unparseable ids through the shared error machinery (the
      # "Error fetching documents" GitHub issue in CI). The gh_issue channel is
      # registered inside #gh_issue, so log at :error after it is set up and
      # before super creates the issue (mirrors
      # Relaton::Iso::DataFetcher#report_errors).
      def report_errors
        gh_issue
        unparseable_ids.each do |content, file|
          log_error "Unparseable primary id `#{content}` was not indexed (#{file})"
        end
        super
      end

      # Parse an ITU docid into a Pubid::Itu identifier, or nil when it can't be
      # parsed or does not round-trip losslessly. Storing the pubid object (not
      # its hash) lets Relaton::Index sort the index and serialize each id to its
      # `_type: pubid:itu:*` hash on save. The round-trip check mirrors the index
      # loader's own Index::FileIO#id_supported? acceptance test, so an id that
      # would make Relaton::Index reject the whole index is dropped at write time.
      # The pinned pubid models recommendations, handbooks and questions, so the
      # guard only skips the few residual forms it can't parse (e.g. "ITU-R RR").
      #
      # @param id [String]
      # @return [::Pubid::Itu::Identifier, nil]
      def pubid(id)
        pid = ::Pubid::Itu.parse id
        hash = pid.to_hash
        return nil unless ::Pubid::Itu::Identifier.from_hash(hash).to_hash == hash

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

      private

      # Fetch the full ITU-T recommendation index in one request.
      # @return [Array<Hash>] rows from the searchRecs "Data" array
      def search_recs
        uri = URI(SEARCH_RECS_URL)
        uri.query = URI.encode_www_form(
          series: -1, type_of_text: -1, sg: -1, main_edition_flag: 0,
          rows: 100_000, page: 1, status: "Z", sort_order: "asc"
        )

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/json"
        request["Referer"] = "https://www.itu.int/myworkspace/"
        request["User-Agent"] = USER_AGENT

        response = http.request(request)
        json = JSON.parse(response.body)
        json["Data"] || []
      end

      # @param start [Integer] pagination offset
      # @return [Array<Hash>] search result items
      def search_request(start)
        payload = {
          "Input" => "*", "Start" => start, "Rows" => ROWS,
          "SortBy" => "DATE_NEW", "ExactPhrase" => false,
          "CollectionName" => "ITU-R Publications",
          "CollectionGroup" => "Publications", "Sector" => "r",
          "Criterias" => [], "Topics" => "", "ClientData" => {},
          "Language" => "en", "SearchType" => "All",
        }

        uri = URI(SEARCH_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"
        request["X-Requested-With"] = "XMLHttpRequest"
        request["Referer"] = "https://www.itu.int/net4/itu-t/search/"
        request.body = "json=#{URI.encode_www_form_component(payload.to_json)}"

        response = http.request(request)
        json = JSON.parse(response.body)
        json["results"] || []
      end
    end
  end
end
