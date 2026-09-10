# pubid loads with the flavor, for the ::Pubid::Ogc::Identifier that the
# index code names. Processor#remove_index_file names no pubid class: the
# delete never reads the index (see lib/relaton/index/CLAUDE.md).
require "pubid"
require "relaton/index"
require "relaton/iso"
require_relative "version"
require_relative "ogc/util"
require_relative "ogc/item_data"
require_relative "ogc/item"
require_relative "ogc/bibitem"
require_relative "ogc/bibdata"
require_relative "ogc/hit_collection"
require_relative "ogc/bibliography"

module Relaton
  module Ogc
    INDEXFILE = "index-v2".freeze
    class Error < StandardError; end

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
