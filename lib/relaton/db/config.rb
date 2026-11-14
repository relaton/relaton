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
      #
      # @!attribute use_api
      #   @return [Boolean] true: a cache miss asks api.relaton.org first,
      #     and the flavor answers what the API does not (relaton#535).
      #     Default false.
      # @!attribute api_timeout
      #   @return [Numeric] open and read timeout of an API request, seconds
      attr_accessor :use_api, :api_host, :api_timeout, :offline

      def initialize
        @use_api = false
        @api_host = "https://api.relaton.org"
        @api_timeout = 10
        @offline = OFFLINE_ON.include?(ENV["RELATON_OFFLINE"].to_s.downcase)
      end
    end

    extend Config
  end
end
