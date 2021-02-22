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
      @logs = %i(warning error)
      @use_api = false # @TODO change to true when we start using api.relaton.org
    end
  end

  extend Config
end
