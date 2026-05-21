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
      attr_accessor :use_api, :api_host

      def initialize
        @use_api = false
        @api_host = "https://api.relaton.org"
      end
    end

    extend Config
  end
end
