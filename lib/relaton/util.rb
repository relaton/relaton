module Relaton
  module Util
    def self.log(message, type = :info)
      log_types = Relaton.configuration.logs.map(&:to_s) || []

      if log_types.include?(type.to_s)
        puts(message)
      end
    end
  end
end
