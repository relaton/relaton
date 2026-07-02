require "relaton/index"
require "relaton/core"
require_relative "calconnect/version"
require_relative "calconnect/model/item"
require_relative "calconnect/util"
require_relative "calconnect/model/bibitem"
require_relative "calconnect/model/bibdata"
require_relative "calconnect/bibliography"
require_relative "calconnect/hit_collection"
require_relative "calconnect/hit"
require_relative "calconnect/scraper"

module Relaton
  module Calconnect
    INDEXFILE = "index-v1".freeze

    # Returns hash of XML reammar
    # @return [String]
    def self.grammar_hash
      # gem_path = File.expand_path "..", __dir__
      # grammars_path = File.join gem_path, "grammars", "*"
      # grammars = Dir[grammars_path].sort.map { |gp| File.read gp }.join
      Digest::MD5.hexdigest Relaton::Calconnect::VERSION + Relaton::Bib::VERSION # grammars
    end
  end
end
