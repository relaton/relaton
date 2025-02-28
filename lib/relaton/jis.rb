# frozen_string_literal: true

require "mechanize"
require "relaton/iso"
require "relaton/index"
require_relative "jis/version"
require_relative "jis/util"
# require_relative "relaton_jis/document_type"
require_relative "jis/item"
require_relative "jis/bibitem"
require_relative "jis/bibdata"
# require_relative "relaton_jis/xml_parser"
# require_relative "relaton_jis/hash_converter"
# require_relative "relaton_jis/scraper"
# require_relative "relaton_jis/bibliography"
# require_relative "relaton_jis/hit_collection"
# require_relative "relaton_jis/hit"
# require_relative "relaton_jis/data_fetcher"

module Relaton
  module Jis
    class Error < StandardError; end

    # Returns hash of XML reammar
    # @return [String]
    def self.grammar_hash
      # gem_path = File.expand_path "..", __dir__
      # grammars_path = File.join gem_path, "grammars", "*"
      # grammars = Dir[grammars_path].sort.map { |gp| File.read gp }.join
      Digest::MD5.hexdigest Relaton::Jis::VERSION + Relaton::Iso::VERSION + Relaton::Bib::VERSION # grammars
    end
  end
end
