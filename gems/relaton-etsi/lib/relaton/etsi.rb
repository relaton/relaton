# frozen_string_literal: true

require "net/http"
require "mechanize"
require "relaton/index"
require_relative "etsi/version"
# require_relative "relaton_etsi/pubid"
require_relative "etsi/bibitem"
require_relative "etsi/bibdata"
require_relative "etsi/util"
require_relative "etsi/bibliography"

module Relaton
  module Etsi
    INDEX_FILE = "index-v1.yaml"

    # Returns hash of gem versions used to generate data model.
    # @return [String]
    def grammar_hash
      Digest::MD5.hexdigest Relaton::Etsi::VERSION + Relaton::Bib::VERSION
    end

    extend self
  end
end
