require "digest/md5"
require "pubid"
require_relative "bib"
require_relative "index"
require_relative "version"

# Relaton::Eu is the EU legal acts flavor (relaton#44): regulations,
# directives and decisions, cited as `EU Regulation 1227/2011`.
#
# `DataFetcher` crawls the Publications Office CELLAR SPARQL endpoint into the
# `relaton-data-eu` data repo with a pubid `index-v2`, and `Bibliography`
# reads that index. See docs/eu.md.
module Relaton
  module Eu
    INDEXFILE = "index-v2".freeze
    # The machine index on the data repo's Pages site (relaton#206).
    PAGES_URL = "https://relaton.github.io/relaton-data-eu/".freeze
    # Where the documents the index names are read from.
    ENDPOINT = "https://raw.githubusercontent.com/relaton/relaton-data-eu/main/".freeze

    autoload :Util,         "relaton/eu/util"
    autoload :Cellar,       "relaton/eu/cellar"
    autoload :Parser,       "relaton/eu/parser"
    autoload :Bibliography, "relaton/eu/bibliography"
    autoload :DataFetcher,  "relaton/eu/data_fetcher"
    autoload :Processor,    "relaton/eu/processor"

    # Returns hash of XML grammar
    # @return [String]
    def self.grammar_hash
      Digest::MD5.hexdigest Relaton::VERSION
    end
  end
end
