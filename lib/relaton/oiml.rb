require "relaton/bib"
require "relaton/index"
require "pubid"
require_relative "version"
require_relative "oiml/util"
require_relative "oiml/docidentifier"
require_relative "oiml/item"
require_relative "oiml/bibitem"
require_relative "oiml/bibdata"
require_relative "oiml/bibliography"

module Relaton
  module Oiml
    INDEXFILE = "index-v2".freeze
    # The machine index on the data repo's Pages site (relaton#206) —
    # manifest + per-shard rows read by the consumer's index; the zip stays
    # on the Pages site for the whole-index retry on a miss.
    PAGES_URL = "https://relaton.github.io/relaton-data-oiml/"

    class Error < StandardError; end

    # Returns hash of XML grammar
    # @return [String]
    def self.grammar_hash
      Digest::MD5.hexdigest Relaton::VERSION
    end
  end
end
