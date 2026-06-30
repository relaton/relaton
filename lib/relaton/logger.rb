# frozen_string_literal: true

require "forwardable"
require "logger"
require_relative "logger/version"
require_relative "logger/log"
require_relative "logger/log_device"
require_relative "logger/pool"
require_relative "logger/formatter_string"
require_relative "logger/formatter_json"
require_relative "logger/config"
require_relative "logger/channels/gh_issue"

module Relaton
  def self.logger_pool
    Logger.configuration.logger_pool
  end
end
