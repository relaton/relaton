require "relaton/bib"
require "relaton/index"
require "pubid"
require_relative "version"
require_relative "jcgm/util"
require_relative "jcgm/docidentifier"
require_relative "jcgm/item"
require_relative "jcgm/bibitem"
require_relative "jcgm/bibdata"
require_relative "jcgm/bibliography"

module Relaton
  module Jcgm
    INDEXFILE = "index-v1".freeze
    # The machine index on the data repo's Pages site (relaton#206) —
    # manifest + per-shard rows read by the consumer's index; the zip stays
    # on the Pages site for the whole-index retry on a miss.
    PAGES_URL = "https://relaton.github.io/relaton-data-jcgm/"

    class Error < StandardError; end

    # Returns hash of XML grammar
    # @return [String]
    def self.grammar_hash
      Digest::MD5.hexdigest Relaton::VERSION
    end
  end
end
