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

      STANDARDS_URL = "https://www.oasis-open.org/standards/".freeze

      def fetch(_source = nil)
        doc = Nokogiri::HTML fetch_html(STANDARDS_URL)
        doc.xpath("//details").map do |item|
          save_doc DataParser.new(item, @errors).parse
          fetch_parts item
        end
        index.save
        report_errors
      end

      private

      # OASIS sits behind Cloudflare, which 403s Ruby Net::HTTP from
      # GitHub Actions runners regardless of User-Agent. libcurl's TLS
      # fingerprint isn't blocked, so fall back to a curl shellout when
      # Mechanize is rejected.
      def fetch_html(url)
        agent = Mechanize.new
        agent.user_agent_alias = "Mac Safari"
        agent.request_headers = {
          "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
          "Accept-Language" => "en-US,en;q=0.5",
        }
        agent.get(url).body
      rescue Mechanize::ResponseCodeError => e
        raise unless e.response_code == "403"

        curl_get(url)
      end

      def curl_get(url)
        ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " \
             "AppleWebKit/605.1.15 (KHTML, like Gecko) " \
             "Version/17.4 Safari/605.1.15"
        body = IO.popen(
          ["curl", "-fsSL", "--retry", "2", "-A", ua,
           "-H", "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
           "-H", "Accept-Language: en-US,en;q=0.5",
           url],
          &:read
        )
        raise "curl failed (exit=#{$?.exitstatus}) for #{url}" unless $?.success?

        body
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
