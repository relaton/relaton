require "relaton/iso"
require_relative "bsi/version"
require_relative "bsi/util"
require_relative "bsi/item_data"
require_relative "bsi/model/item"
require_relative "bsi/model/relation"
require_relative "bsi/model/bibitem"
require_relative "bsi/model/bibdata"
require_relative "bsi/scraper"
require_relative "bsi/hit_collection"
require_relative "bsi/hit"
require_relative "bsi/bibliography"

module Relaton
  module Bsi
    # Returns hash of XML greammar
    # @return [String]
    def self.grammar_hash
      # gem_path = File.expand_path "..", __dir__
      # grammars_path = File.join gem_path, "grammars", "*"
      # grammars = Dir[grammars_path].sort.map { |gp| File.read gp }.join
      Digest::MD5.hexdigest Relaton::Bsi::VERSION + Relaton::Iso::VERSION + Relaton::Bib::VERSION # grammars
    end
  end
end
