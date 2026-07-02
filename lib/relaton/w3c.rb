require "relaton/bib"
require "relaton/index"
require_relative "w3c/version"
require_relative "w3c/util"
require_relative "w3c/item"
require_relative "w3c/bibitem"
require_relative "w3c/bibdata"
require_relative "w3c/bibliography"

module Relaton
  module W3c
    INDEXFILE = "index-v1".freeze

    class Error < StandardError; end

    # Returns hash of XML reammar
    # @return [String]
    def self.grammar_hash
      # gem_path = File.expand_path "..", __dir__
      # grammars_path = File.join gem_path, "grammars", "*"
      # grammars = Dir[grammars_path].sort.map { |gp| File.read gp }.join
      Digest::MD5.hexdigest Relaton::W3c::VERSION + Relaton::Bib::VERSION # grammars
    end
  end
end
