# frozen_string_literal: true

require "net/http"
require "mechanize"
require "pubid"
require "relaton/iso"
require "relaton/index"
require_relative "jis/version"
require_relative "jis/util"
require_relative "jis/item"
require_relative "jis/bibitem"
require_relative "jis/bibdata"
require_relative "jis/hit_collection"
require_relative "jis/bibliography"

module Relaton
  module Jis
    INDEXFILE = "index-v1"
    # Pubid-based index produced alongside index-v1 during the pubid migration.
    INDEXFILE_V2 = "index-v2"

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
