module Relaton::Logger
  class Log < ::Logger
    attr_reader :levels

    def initialize(logdev, shift_age = 0, shift_size = 1_048_576, **args) # rubocop:disable Lint/MissingSuper
      self.levels = args.delete(:levels) || [UNKNOWN, FATAL, ERROR, WARN, INFO]
      self.level = @levels.min
      self.progname = args.delete(:progname)
      @default_formatter = FormatterString.new
      self.datetime_format = args.delete(:datetime_format)
      self.formatter = args.delete(:formatter)
      self.formatter = self.formatter.new if self.formatter.is_a? Class
      @logdev = nil
      @level_override = {}
      if logdev && logdev != File::NULL
        @logdev = LogDevice.new(logdev, shift_age: shift_age, shift_size: shift_size, **args)
      end
    end

    def levels=(levels)
      @levels = Set.new levels.map { |l| Severity.coerce l }
      self.level = @levels.min
    end

    def add_level(level)
      @levels << Severity.coerce(level)
      self.level = @levels.min
    end

    def remove_level(level)
      @levels.delete Severity.coerce(level)
      self.level = @levels.min
    end

    def unknown(message = nil, progname = nil, **args, &block)
      level = Object.const_get "Logger::#{__callee__.to_s.upcase}"
      add(level, message, progname, **args, &block)
    end

    %i[fatal error warn info debug].each { |m| alias_method m, :unknown }

    def add(severity, message = nil, progname = nil, **args) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
      severity ||= UNKNOWN
      return true if @logdev.nil? || !@levels.include?(severity)

      if block_given?
        progname ||= message || @progname
        message = yield
      else
        progname ||= @progname
      end
      @logdev.write format_message(format_severity(severity), Time.now, progname, message, **args)
      true
    end

    def format_message(severity, datetime, progname, msg, **args)
      (@formatter || @default_formatter).call(severity, datetime, progname, msg, **args)
    end

    def truncate
      @logdev.truncate
    end
  end
end
