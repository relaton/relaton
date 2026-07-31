require "digest/md5"
require "faraday"
require "yaml"
require "pubid"
require "relaton/index"
require "relaton/bib"
require_relative "version"
require_relative "ieee/util"
require_relative "ieee/bibliography"
require_relative "ieee/item_data"
require_relative "ieee/item"
require_relative "ieee/bibitem"
require_relative "ieee/bibdata"

module Relaton
  module Ieee
    class Error < StandardError; end

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
