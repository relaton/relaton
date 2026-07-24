require "mechanize"
require "parslet"
require "pubid"
require "digest/md5"
require "relaton/index"
require "relaton/bib"
require "relaton/core"
require_relative "version"
require_relative "itu/util"
require_relative "itu/item_data"
require_relative "itu/model/item"
require_relative "itu/model/bibitem"
require_relative "itu/model/bibdata"
require_relative "itu/pubid"
require_relative "itu/scraper"
require_relative "itu/hit_collection"
require_relative "itu/bibliography"

module Relaton
  module Itu
    INDEXFILE = "index-v2"

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
