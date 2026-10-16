require "relaton/bib"
require "relaton/index"
require "pubid"
require_relative "version"
require_relative "iho/util"
require_relative "iho/docidentifier"
require_relative "iho/item"
require_relative "iho/bibitem"
require_relative "iho/bibdata"
require_relative "iho/bibliography"

module Relaton
  module Iho
    INDEXFILE = "index-v3".freeze
    # The machine index on the data repo's Pages site (relaton#206) —
    # manifest + per-shard rows read by the consumer's index; the zip stays
    # on the Pages site for the whole-index retry on a miss.
    PAGES_URL = "https://relaton.github.io/relaton-data-iho/"

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
