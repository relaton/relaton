module Relaton::Logger
  module Config
    def configure
      yield configuration if block_given?
    end

    def configuration
      @configuration ||= self::Configuration.new
    end
  end

  class Configuration
    # @return [Array<Relaton::Logger::Log>] List of loggers
    attr_reader :logger_pool

    def initialize
      @logger_pool ||= Pool.new
      @logger_pool[:default] = Log.new($stderr, levels: %i[info warn error fatal])
    end

    #
    # Replace the current list of loggers with the given list of loggers.
    #
    # @param [Array<Relaton::Logger::Log>] loggers list of loggers
    #
    # @return [void]
    #
    def logger_pool=(loggers)
      @logger_pool.loggers = loggers
    end
  end

  extend Config
end
