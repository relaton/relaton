require "ferrum"
require "nokogiri"
require_relative "../oasis"
require_relative "data_parser_utils"
require_relative "data_parser"
require_relative "data_part_parser"

module Relaton
  module Oasis
    # Thin Ferrum-backed agent that drives headless Chrome with stealth tweaks
    # so the Cloudflare-protected oasis-open.org host serves real HTML instead
    # of a "Just a moment..." challenge. Mirrors the pattern used by
    # Relaton::Cie::BrowserAgent.
    class BrowserAgent
      UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
           "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
      CHALLENGE_MARKERS = ["Just a moment", "challenge-platform"].freeze
      MAX_CHALLENGE_WAIT = 30

      def initialize
        @browser = Ferrum::Browser.new(
          headless: true,
          timeout: 90,
          process_timeout: 90,
          window_size: [1366, 768],
          browser_options: {
            "disable-blink-features" => "AutomationControlled",
            "disable-quic" => nil,
            "no-sandbox" => nil,
          },
        )
        @browser.headers.set(
          "Accept-Language" => "en-US,en;q=0.9",
          "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9," \
                      "image/webp,*/*;q=0.8",
          "User-Agent" => UA,
        )
        @browser.evaluate_on_new_document(<<~JS)
          Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
          Object.defineProperty(navigator, 'languages', { get: () => ['en-US', 'en'] });
          Object.defineProperty(navigator, 'plugins', { get: () => [1,2,3,4,5] });
          window.chrome = { runtime: {} };
        JS
      end

      def get(url)
        @browser.go_to(url)
        wait_for_challenge
        Nokogiri::HTML(@browser.body)
      end

      def quit
        @browser&.quit
      ensure
        @browser = nil
      end

      private

      def wait_for_challenge
        MAX_CHALLENGE_WAIT.times do
          return unless CHALLENGE_MARKERS.any? { |m| @browser.body.include?(m) }

          sleep 1
        end
      end
    end

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
          save_doc DataParser.new(item, @errors).parse
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
