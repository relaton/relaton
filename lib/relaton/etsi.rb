# frozen_string_literal: true

require "net/http"
require "mechanize"
require "pubid"
require "relaton/index"
require_relative "version"
# require_relative "relaton_etsi/pubid"
require_relative "etsi/bibitem"
require_relative "etsi/bibdata"
require_relative "etsi/util"
require_relative "etsi/bibliography"

module Relaton
  module Etsi
    INDEXFILE = "index-v2".freeze

    # Returns hash of gem versions used to generate data model.
    # @return [String]
    def grammar_hash
      Digest::MD5.hexdigest Relaton::VERSION
    end

    extend self
  end
end
