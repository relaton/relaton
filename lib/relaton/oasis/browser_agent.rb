require "ferrum"
require "nokogiri"

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

      # HTTP status code of the most recent navigation's main resource,
      # or nil if no navigation has happened yet.
      def last_status
        @browser&.network&.status
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
  end
end
