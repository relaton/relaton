require "date"
require "mechanize"
require "csv"
require "relaton/core"
require "relaton/index"
require_relative "../etsi"
require_relative "data_parser"

module Relaton
  module Etsi
    class DataFetcher < Core::DataFetcher
      SOURCEURL = "https://www.etsi.org/?option=com_standardssearch&view=data&format=csv&includeScope=1&" \
        "page=1&search=&title=1&etsiNumber=1&content=1&version=0&onApproval=1&published=1&withdrawn=1&" \
        "historical=1&isCurrent=1&superseded=1&startDate=1988-01-15&endDate=%<date>s&harmonized=0&" \
        "keyword=&TB=&stdType=&frequency=&mandate=&collection=&sort=1&x=%<timestamp>s".freeze

      def index
        @index ||= Relaton::Index.find_or_create :etsi, file: INDEX_FILE
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
        time = Time.now
        date = time.to_date + 1
        timestamp = (time.to_f * 1000).to_i
        url = format(SOURCEURL, date: date, timestamp: timestamp)
        csv = fetch_with_retry(url)
        CSV.parse(csv, headers: true, col_sep: ";", skip_lines: /sep=;/).each do |row|
          save DataParser.new(row, @errors).parse
        end
        index.save
        report_errors
      end

      NETWORK_ERRORS = [
        Mechanize::Error, Net::OpenTimeout, Net::ReadTimeout,
        SocketError, Errno::ECONNRESET
      ].freeze

      def fetch_with_retry(url, retries: 3, delay: 2) # rubocop:disable Metrics/MethodLength
        attempt = 0
        begin
          Mechanize.new.get(url).body
        rescue *NETWORK_ERRORS => e
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
        file = output_file id
        File.write file, serialize(bib), encoding: "UTF-8"
        index.add_or_update id, file
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
