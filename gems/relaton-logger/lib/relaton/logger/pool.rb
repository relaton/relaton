module Relaton::Logger
  class Pool
    extend Forwardable
    def_delegators :@loggers, :[], :[]=, :size, :each

    attr_accessor :loggers

    def initialize
      @loggers = {}
    end

    def unknown(message = nil, progname = nil, **args, &block)
      @loggers.each { |_, logger| logger.send(__callee__, message, progname, **args, &block) }
      nil
    end

    %i[fatal error warn info debug].each { |m| alias_method m, :unknown }

    def truncate
      @loggers.each { |_, logger| logger.truncate }
      nil
    end
  end
end
