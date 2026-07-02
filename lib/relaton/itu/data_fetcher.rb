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
        @index ||= Relaton::Index.find_or_create :itu, file: "index-v1.yaml"
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
        index.add_or_update id, file
        File.write file, serialize(bib), encoding: "UTF-8"
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
