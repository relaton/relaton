module Relaton
  class Db
    module Config
      def configure
        yield configuration if block_given?
      end

      def configuration
        @configuration ||= Configuration.new
      end
    end

    class Configuration
      # Values of RELATON_OFFLINE that turn offline mode on.
      OFFLINE_ON = %w[1 true yes on].freeze

      # @!attribute offline
      #   @return [Boolean] true: every fetch is answered from the local
      #     store only, and a miss raises Relaton::NotInLocalStoreError
      #     (relaton#536). Defaults to RELATON_OFFLINE.
      attr_accessor :use_api, :api_host, :offline

      def initialize
        @use_api = false
        @api_host = "https://api.relaton.org"
        @offline = OFFLINE_ON.include?(ENV["RELATON_OFFLINE"].to_s.downcase)
      end
    end

    extend Config
  end
end
