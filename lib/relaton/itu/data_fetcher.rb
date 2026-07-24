require "net/http"
require "json"
require "uri"
require_relative "../itu"
require_relative "data_parser_r"

module Relaton
  module Itu
    class DataFetcher < Core::DataFetcher
      SEARCH_URL = "https://www.itu.int/net4/ITU-T/search/GlobalSearch/RunSearch".freeze
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

      def fetch(_source = nil)
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
        index.save
        report_errors
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
