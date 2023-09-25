module Relaton
  module Config
    include RelatonBib::Config
  end
  extend Config

  class Configuration < RelatonBib::Configuration
    PROGNAME = "relaton".freeze

    attr_accessor :use_api, :api_host

    def initialize
      super
      @use_api = false
      @api_host = "https://api.relaton.org"
    end
  end
end
