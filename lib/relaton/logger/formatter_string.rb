module Relaton::Logger
  class FormatterString < ::Logger::Formatter
    def call(severity, _datetime, progname, msg, **args)
      output = []
      output << "[#{progname}]" if progname
      output << "#{severity}:"
      output << "(#{args[:key]})" if args[:key]
      output << "#{msg}\n"
      output.join " "
    end
  end
end
