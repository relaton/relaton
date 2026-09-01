module Relaton
  module Ecma
    class PageFetcher
      RETRIES = 3

      def initialize
        @agent = Mechanize.new
        @agent.user_agent_alias = Mechanize::AGENT_ALIASES.keys[rand(21)]
      end

      #
      # Get page with retries
      #
      # A failed fetch must raise, not fall out of the loop. `RETRIES.times`
      # returns its receiver, so the exhausted loop used to hand the caller the
      # Integer 3 as if it were a page, and `StandardParser#fetch_title`
      # reported the transport error as `undefined method 'xpath' for an
      # instance of Integer`. `DataFetcher#html_index` already rescues per hit,
      # so one unreachable page is skipped with a readable message.
      #
      # @param [String] url url to fetch
      #
      # @return [Mechanize::Page] document
      # @raise [Relaton::RequestError] after RETRIES attempts
      #
      def get(url)
        error = nil
        RETRIES.times do |n|
          sleep n
          return @agent.get url
        rescue StandardError => e
          error = e
          Util.error e.message
        end
        raise Relaton::RequestError, "Could not access #{url}: #{error.message}"
      end
    end
  end
end
