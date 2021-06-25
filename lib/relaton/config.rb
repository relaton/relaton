module Relaton
  module Config
    def configure
      if block_given?
        yield configuration
      end
    end

    def configuration
      @configuration ||= Configuration.new
    end
  end

  class Configuration
    attr_accessor :logs, :use_api, :api_host, :api_mode

    def initialize
      @logs = %i(info error) # allowed values: :info, :warning, :error, :debug

      # @TODO change to true when we start using api.relaton.org
      @use_api = true
      @api_mode = false
      @api_host = nil # "http://0.0.0.0:9292"
    end
  end

  extend Config
end
