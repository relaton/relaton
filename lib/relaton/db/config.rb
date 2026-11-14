require "uri"

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
      # Values of a `RELATON_*` switch (any case) that turn it on.
      SWITCH_ON = %w[1 true yes on].freeze
      # Values of RELATON_OFFLINE that turn offline mode on.
      OFFLINE_ON = SWITCH_ON
      DEFAULT_API_HOST = "https://api.relaton.org".freeze

      # @!attribute offline
      #   @return [Boolean] true: every fetch is answered from the local
      #     store only, and a miss raises Relaton::NotInLocalStoreError
      #     (relaton#536). Defaults to RELATON_OFFLINE.
      #
      # @!attribute use_api
      #   @return [Boolean] true: a cache miss asks api.relaton.org first,
      #     and the flavor answers what the API does not (relaton#535).
      #     Defaults to RELATON_USE_API, else false. The CLI's `--api` /
      #     `--no-api` sets it for one run.
      # @!attribute api_host
      #   @return [String] the API's base URL. Defaults to RELATON_API_HOST,
      #     else https://api.relaton.org.
      # @!attribute api_timeout
      #   @return [Numeric] open and read timeout of an API request, seconds
      attr_accessor :use_api, :api_host, :api_timeout, :offline

      def initialize
        @use_api = switch? "RELATON_USE_API"
        @api_host = env_api_host || DEFAULT_API_HOST
        @api_timeout = 10
        @offline = switch? "RELATON_OFFLINE"
      end

      private

      def switch?(name)
        SWITCH_ON.include? ENV[name].to_s.downcase
      end

      # RELATON_API_HOST, when it is an http(s) URL with a host. A shell
      # value is easy to write without its scheme (`api.example.org`), and
      # the resolver would then ask a host-less URI; that is warned about,
      # not used.
      def env_api_host
        host = ENV["RELATON_API_HOST"].to_s.strip
        return if host.empty?

        uri = URI.parse(host)
        return host if uri.is_a?(URI::HTTP) && uri.host && !uri.host.empty?

        invalid_api_host host
      rescue URI::InvalidURIError
        invalid_api_host host
      end

      def invalid_api_host(host)
        Util.warn "RELATON_API_HOST #{host.inspect} is not an http(s) URL; " \
                  "using #{DEFAULT_API_HOST}"
        nil
      end
    end

    extend Config
  end
end
