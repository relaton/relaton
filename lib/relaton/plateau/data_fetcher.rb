require "json"
require "relaton/core"
require_relative "../plateau"
require_relative "parser"
require_relative "handbook_parser"
require_relative "technical_report_parser"

module Relaton
  module Plateau
    # Fetcher class to fetch data from the Plateau website
    class DataFetcher < Core::DataFetcher
      HANDBOOKS_URL = "https://www.mlit.go.jp/plateau/_next/data/1.3.0/libraries/handbooks.json".freeze
      TECHNICAL_REPORTS_URL = "https://www.mlit.go.jp/plateau/_next/data/1.3.0/libraries/technical-reports.json".freeze

      def index
        @index ||= Relaton::Index.find_or_create :plateau, file: "#{INDEXFILE}.yaml"
      end

      def log_error(msg)
        Util.error msg
      end

      def fetch(source)
        case source
        when "plateau-handbooks" then extract_handbooks_data
        when "plateau-technical-reports" then extract_technical_reports_data
        else puts "Invalid source: #{source}"
        end
      end

      # Create a GET request with custom headers to mimic a browser
      def create_request(uri)
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:127.0) Gecko/20100101 Firefox/127.0"
        request["Accept"] = "*/*"
        request["Accept-Language"] = "en-US,en;q=0.5"
        request["Accept-Encoding"] = "gzip, deflate, br, zstd"
        request["Referer"] = "https://www.mlit.go.jp/plateau/libraries/"
        request["purpose"] = "prefetch"
        request["x-nextjs-data"] = "1"
        request["Connection"] = "keep-alive"
        request
      end

      # Handle different content encodings
      def hadle_response(response)
        if response["Content-Encoding"] == "gzip"
          Zlib::GzipReader.new(StringIO.new(response.body)).read
        elsif response["Content-Encoding"] == "deflate"
          Zlib::Inflate.inflate(response.body)
        else
          response.body
        end
      end

      # Fetch JSON data from a URL with custom headers
      #
      # @param [String] url The URL to fetch JSON data from
      # @return [Hash] The parsed JSON data
      def fetch_json_data(url)
        uri = URI(url)

        request = create_request(uri)

        # Send the request and get the response
        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.request(request)
        end

        # Check if the response is successful
        unless response.code.to_i == 200
          Util.warn "Failed to fetch data: #{response.code} #{response.message}"
          return {}
        end

        body = hadle_response(response)

        # Parse the JSON response
        JSON.parse(body)
      rescue StandardError => e
        # Handle any errors during the fetching process
        Util.error "Error fetching JSON data from #{url}: #{e.message}"
        {}
      end

      #
      # Extract data for handbooks
      #
      def extract_handbooks_data
        data = fetch_json_data(HANDBOOKS_URL)
        Util.info "Extracting handbooks data..."
        data["pageProps"]["handbooks"]["nodes"].each do |entry|
          handbook = entry["handbook"]
          doctype = entry["slug"].match("-") ? "annex" : "handbook"

          handbook["versions"].each do |version|
            item = HandbookParser.new(version: version, entry: entry, doctype: doctype, errors: @errors).parse
            save_document(item)
          end
        end
        index.save
        report_errors
      end

      #
      # Extract data for technical reports
      #
      def extract_technical_reports_data
        data = fetch_json_data(TECHNICAL_REPORTS_URL)
        Util.info "Extracting technical reports data..."
        data["pageProps"]["nodes"].map do |entry|
          save_document(TechnicalReportParser.new(entry, @errors).parse)
        end
        index.save
        report_errors
      end

      def save_document(item)
        id = item.docidentifier.first.content
        file = file_name id
        if @files.include?(file)
          Util.warn "File #{file} already exists, skipping.", key: id
        else
          File.write(file, serialize(item))
          @files << file
          index.add_or_update id, file
        end
      end

      def file_name(id)
        name = id.gsub(/\s+/, "-").gsub(/[^\w-]+/, "").downcase
        if id.match?(/民間活用編/)
          name += "-private"
        elsif id.match?(/公共活用編/)
          name += "-public"
        end
        File.join(@output, "#{name}.#{@ext}")
      end

      def to_yaml(bib)
        Item.to_yaml(bib)
      end

      def to_xml(bib)
        Item.to_xml(bib, bibdata: true)
      end

      def to_bibxml(bib)
        bib.to_rfcxml
      end
    end
  end
end
