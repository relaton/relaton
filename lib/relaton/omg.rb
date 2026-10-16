require "moxml"
require "relaton/bib"
require_relative "version"
require_relative "omg/util"
require_relative "omg/ext"
require_relative "omg/docidentifier"
require_relative "omg/item_data"
require_relative "omg/item"
require_relative "omg/bibitem"
require_relative "omg/bibdata"
require_relative "omg/scraper"
require_relative "omg/bibliography"

module Relaton
  module Omg
    # The flavor's published index on relaton-data-omg (relaton#206): the
    # machine index the Pages site serves, built from the crawled
    # data/*.yaml with pubid_class ::Pubid::Omg::Identifier. relaton-data-omg
    # supersedes the flavor's earlier "no index, no data repository" shape —
    # the crawler and the Pages site are live.
    INDEXFILE = "index-v2"
    # The machine index on the data repo's Pages site (relaton#206) — the
    # manifest + whole-index zip the consumer reads; the crawl does not cover
    # every spec, so Bibliography falls back to the live scrape on a miss.
    PAGES_URL = "https://relaton.github.io/relaton-data-omg/"

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
