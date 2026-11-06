require "digest/md5"
require "pubid"
require_relative "bib"
require_relative "index"
require_relative "version"

# Relaton::Sae is the SAE International flavor (relaton/relaton-sae#1).
#
# sae.org answers a script with a CAPTCHA, so the flavor reads SAE's Crossref
# deposits instead: every SAE standard edition has its own DOI
# (`10.4271/j3016_202104`). `DataFetcher` crawls them into the
# `relaton-data-sae` data repo with a pubid `index-v2`, and `Bibliography`
# reads that index. See docs/sae.md.
module Relaton
  module Sae
    INDEXFILE = "index-v2".freeze
    # The machine index on the data repo's Pages site (relaton#206).
    PAGES_URL = "https://relaton.github.io/relaton-data-sae/".freeze
    # Where the documents the index names are read from.
    ENDPOINT = "https://raw.githubusercontent.com/relaton/relaton-data-sae/main/".freeze

    autoload :Util,         "relaton/sae/util"
    autoload :DoiCode,      "relaton/sae/doi_code"
    autoload :ItemData,     "relaton/sae/item_data"
    autoload :Item,         "relaton/sae/item"
    autoload :Bibitem,      "relaton/sae/bibitem"
    autoload :Bibdata,      "relaton/sae/bibdata"
    autoload :Bibliography, "relaton/sae/bibliography"
    autoload :Processor,    "relaton/sae/processor"

    # Returns hash of XML grammar
    # @return [String]
    def self.grammar_hash
      Digest::MD5.hexdigest Relaton::VERSION
    end
  end
end
