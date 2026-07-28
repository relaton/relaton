# frozen_string_literal: true

require "relaton/bib"
require "relaton/index"
require "relaton/version"

# Relaton::Gost is the GOST (Russian federal standards — Гостстандарт)
# flavor of the unified relaton gem. Adds typed Ext fields (urn,
# webpage) so they round-trip natively through YAML and XML without
# per-repo merge hacks.
module Relaton
  module Gost
    INDEXFILE = "index-v2".freeze

    class Error < StandardError; end

    autoload :Doctype,       "relaton/gost/doctype"
    autoload :Ext,           "relaton/gost/ext"
    autoload :ItemData,      "relaton/gost/item_data"
    autoload :ItemBase,      "relaton/gost/item_base"
    autoload :Item,          "relaton/gost/item"
    autoload :Bibitem,       "relaton/gost/bibitem"
    autoload :Bibdata,       "relaton/gost/bibdata"
    autoload :Docidentifier, "relaton/gost/docidentifier"
    autoload :Bibliography,  "relaton/gost/bibliography"
    autoload :Util,          "relaton/gost/util"
    autoload :Processor,     "relaton/gost/processor"

    # Returns hash of XML grammar
    # @return [String]
    def self.grammar_hash
      Digest::MD5.hexdigest Relaton::VERSION
    end
  end
end
