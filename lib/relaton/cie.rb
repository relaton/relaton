require "moxml"
# require "parslet"
require "pubid"
require "relaton/index"
require "relaton/bib"
# require "relaton_bib/name_parser"
require_relative "version"
require_relative "cie/util"
require_relative "cie/item_data"
require_relative "cie/item"
require_relative "cie/bibitem"
require_relative "cie/bibdata"
require_relative "cie/bibliography"
require_relative "cie/scrapper"

module Relaton
  module Cie
    INDEXFILE = "index-v2".freeze
    # The machine index on the data repo's Pages site (relaton#206) —
    # manifest + per-shard rows read by the consumer's index; the zip stays
    # on the Pages site for the whole-index retry on a miss.
    PAGES_URL = "https://relaton.github.io/relaton-data-cie/"

    # Returns hash of XML reammar
    # @return [String]
    def self.grammar_hash
      # gem_path = File.expand_path "..", __dir__
      # grammars_path = File.join gem_path, "grammars", "*"
      # grammars = Dir[grammars_path].sort.map { |gp| File.read gp }.join
      Digest::MD5.hexdigest Relaton::VERSION # grammars
    end
  end
end
