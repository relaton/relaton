module Relaton
  module Util
    extend RelatonBib::Util

    def self.logger
      Relaton.configuration.logger
    end
  end
end
