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
    attr_accessor :logs

    def initialize
      @logs ||= %i(warning error)
    end
  end

  extend Config
end
