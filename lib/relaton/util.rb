module Relaton
  module Util
    # @param message [String]
    # @param type [Symbol] default :info
    def self.log(message, type = :info)
      log_types = Relaton.configuration.logs.map(&:to_s) || []

      if log_types.include?(type.to_s)
        warn(message)
      end
    end
  end
end
