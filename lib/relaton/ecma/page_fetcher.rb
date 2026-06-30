module Relaton
  module Ecma
    class PageFetcher
      def initialize
        @agent = Mechanize.new
        @agent.user_agent_alias = Mechanize::AGENT_ALIASES.keys[rand(21)]
      end

      #
      # Get page with retries
      #
      # @param [String] url url to fetch
      #
      # @return [Mechanize::Page] document
      #
      def get(url)
        3.times do |n|
          sleep n
          doc = @agent.get url
          return doc
        rescue StandardError => e
          Util.error e.message
        end
      end
    end
  end
end
