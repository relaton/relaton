# frozen_string_literal: true

module Relaton::Logger
  class LogDevice < ::Logger::LogDevice
    #
    # @param header [Boolean, nil] whether to add header to log file
    #
    def initialize(logdev, **args)
      # TODO: the header is not used yet, maybe it will be used in the future for not JSON formatters
      @header = args.delete :header
      super
    end

    def add_log_header(file)
      return unless @header

      super
    end

    def truncate
      return unless @dev.respond_to? :truncate

      @dev.truncate 0
      @dev.rewind
    end
  end
end
