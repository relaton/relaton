require "yeptris"
module Relaton::Logger
  class FormatterJSON < ::Logger::Formatter
    def call(severity, _datetime, progname, msg, **args)
      hash = { prog: progname, message: msg, severity: severity }.merge(args)
      Yeptris::JSON.dump(hash) + "\n"
    end
  end
end
