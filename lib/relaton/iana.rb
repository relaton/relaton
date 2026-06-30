# frozen_string_literal: true

require "faraday"
require "relaton/index"
require "relaton/bib"
require_relative "iana/version"
require_relative "iana/util"
require_relative "iana/item_data"
require_relative "iana/item"
require_relative "iana/bibitem"
require_relative "iana/bibdata"
require_relative "iana/bibliography"
# require_relative "relaton_iana/parser"
# require_relative "relaton_iana/data_fetcher"

module Relaton
  module Iana
    INDEXFILE = "index-v1"

    # Returns hash of XML reammar
    # @return [String]
    def self.grammar_hash
      # gem_path = File.expand_path "..", __dir__
      # grammars_path = File.join gem_path, "grammars", "*"
      # grammars = Dir[grammars_path].sort.map { |gp| File.read gp }.join
      Digest::MD5.hexdigest Relaton::Iana::VERSION + Relaton::Bib::VERSION # grammars
    end
  end
end
