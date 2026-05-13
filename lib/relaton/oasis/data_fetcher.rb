require "mechanize"
require_relative "../oasis"
require_relative "data_parser_utils"
require_relative "data_parser"
require_relative "data_part_parser"

module Relaton
  module Oasis
    class DataFetcher < Core::DataFetcher
      def log_error(msg)
        Util.error msg
      end

      USER_AGENTS = [
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " \
          "(KHTML, like Gecko) Version/17.4 Safari/605.1.15",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " \
          "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        "Mozilla/5.0 (X11; Linux x86_64; rv:125.0) Gecko/20100101 Firefox/125.0",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14.4; rv:125.0) Gecko/20100101 " \
          "Firefox/125.0",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:125.0) Gecko/20100101 " \
          "Firefox/125.0",
      ].freeze

      MAX_ATTEMPTS = 5
      RETRY_BACKOFF = 2 # seconds, doubled each attempt

      def fetch(_source = nil)
        doc = Nokogiri::HTML fetch_with_retry("https://www.oasis-open.org/standards/")
        doc.xpath("//details").map do |item|
          save_doc DataParser.new(item, @errors).parse
          fetch_parts item
        end
        index.save
        report_errors
      end

      private

      def fetch_with_retry(url)
        last_error = nil
        USER_AGENTS.first(MAX_ATTEMPTS).each_with_index do |ua, i|
          sleep(RETRY_BACKOFF * (2**(i - 1))) if i.positive?
          begin
            Util.info "Fetching #{url} (attempt #{i + 1}/#{MAX_ATTEMPTS}, UA=#{ua[0, 30]}...)"
            return build_agent(ua).get(url).body
          rescue Mechanize::ResponseCodeError => e
            last_error = e
            Util.warn "Attempt #{i + 1} failed: HTTP #{e.response_code}"
            raise unless e.response_code == "403"
          end
        end
        raise last_error
      end

      def build_agent(user_agent)
        agent = Mechanize.new
        agent.user_agent = user_agent
        agent.request_headers = {
          "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
          "Accept-Language" => "en-US,en;q=0.5",
        }
        agent
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

        parts.each { |part| save_doc DataPartParser.new(part, @errors).parse }
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
