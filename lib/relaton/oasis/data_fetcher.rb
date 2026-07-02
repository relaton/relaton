require_relative "../oasis"
require_relative "browser_agent"
require_relative "data_parser_utils"
require_relative "data_parser"
require_relative "data_part_parser"

module Relaton
  module Oasis
    class DataFetcher < Core::DataFetcher
      STANDARDS_URL = "https://www.oasis-open.org/standards/".freeze
      RETRIABLE_ERRORS = [
        SocketError,
        Ferrum::TimeoutError,
        Ferrum::PendingConnectionsError,
        Ferrum::StatusError,
      ].freeze

      def log_error(msg)
        Util.error msg
      end

      def fetch(_source = nil)
        doc = with_retry { agent.get(STANDARDS_URL) }
        doc.xpath("//details").map do |item|
          save_doc DataParser.new(item, @errors, agent: agent).parse
          fetch_parts item
        end
        index.save
        report_errors
      ensure
        @agent&.quit
      end

      private

      def agent
        @agent ||= BrowserAgent.new
      end

      def with_retry
        tries = 0
        begin
          tries += 1
          yield
        rescue *RETRIABLE_ERRORS => e
          retry if tries < 4
          raise e
        end
      end

      def index
        @index ||= Relaton::Index.find_or_create(
          :oasis, file: "#{INDEXFILE}.yaml"
        )
      end

      def fetch_parts(item)
        xpath = "./div/div/div[contains(@class, " \
                "'standard__grid--cite-as')]" \
                "/p[strong or span/strong]"
        parts = item.xpath(xpath)
        return unless parts.size > 1

        parts.each do |part|
          save_doc DataPartParser.new(part, @errors, agent: agent).parse
        end
      end

      def save_doc(doc) # rubocop:disable Metrics/AbcSize
        id = doc.docidentifier.find(&:primary) || doc.docidentifier.first
        file = output_file(id.content)
        if @files.include? file
          Util.warn "File #{file} already exists. Document: #{id.content}"
        else
          @files << file
        end
        index.add_or_update id.content, file
        File.write file, serialize(doc), encoding: "UTF-8"
      end

      def to_xml(bib)
        bib.to_xml(bibdata: true)
      end

      def to_yaml(bib)
        bib.to_yaml
      end

      def to_bibxml(bib)
        bib.to_rfcxml
      end
    end
  end
end
