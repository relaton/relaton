require "net/http"
# pubid loads with the flavor, for the ::Pubid::Tgpp::Identifier that the
# index code names. Processor#remove_index_file names no pubid class: the
# delete never reads the index (see lib/relaton/index/CLAUDE.md).
require "pubid"
require "relaton/index"
require "relaton/core"
require "relaton/bib"
require_relative "version"
require_relative "3gpp/util"
require_relative "3gpp/item"
require_relative "3gpp/bibitem"
require_relative "3gpp/bibdata"
require_relative "3gpp/bibliography"

module Relaton
  module ThreeGpp
    INDEXFILE = "index-v2".freeze

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
