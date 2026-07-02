require "nokogiri"
# require "parslet"
require "relaton/index"
require "relaton/bib"
# require "relaton_bib/name_parser"
require_relative "cie/version"
require_relative "cie/util"
require_relative "cie/item_data"
require_relative "cie/item"
require_relative "cie/bibitem"
require_relative "cie/bibdata"
require_relative "cie/bibliography"
require_relative "cie/scrapper"

module Relaton
  module Cie
    INDEXFILE = "index-v1".freeze

    # Returns hash of XML reammar
    # @return [String]
    def self.grammar_hash
      # gem_path = File.expand_path "..", __dir__
      # grammars_path = File.join gem_path, "grammars", "*"
      # grammars = Dir[grammars_path].sort.map { |gp| File.read gp }.join
      Digest::MD5.hexdigest Relaton::Cie::VERSION + Relaton::Bib::VERSION # grammars
    end
  end
end
