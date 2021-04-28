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
    attr_accessor :logs, :use_api

    def initialize
      @logs = %i(info error) # allowed values: :info, :warning, :error, :debug

      # @TODO change to true when we start using api.relaton.org
      @use_api = false
    end
  end

  extend Config
end
