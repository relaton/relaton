# frozen_string_literal: true

require_relative "bib"
require_relative "index"
require "pubid"
require_relative "version"

# Relaton::Wmo is the World Meteorological Organization flavor of the
# unified relaton gem: the WMO-No. series, WMO/TD technical documents,
# JCOMM technical reports and GAW reports, keyed by Pubid::Wmo
# (pubid#763 + the widening round). Adds typed Ext fields (doctype, urn,
# webpage) so they round-trip natively through YAML and XML.
module Relaton
  module Wmo
    INDEXFILE = "index-v2".freeze
    # The machine index on the data repo's Pages site (relaton#206) —
    # manifest + per-shard rows read by the consumer's index; the zip stays
    # on the Pages site for the whole-index retry on a miss.
    PAGES_URL = "https://relaton.github.io/relaton-data-wmo/"

    class Error < StandardError; end

    autoload :Doctype,       "relaton/wmo/doctype"
    autoload :Ext,           "relaton/wmo/ext"
    autoload :ItemData,      "relaton/wmo/item_data"
    autoload :ItemBase,      "relaton/wmo/item_base"
    autoload :Item,          "relaton/wmo/item"
    autoload :Bibitem,       "relaton/wmo/bibitem"
    autoload :Bibdata,       "relaton/wmo/bibdata"
    autoload :Docidentifier, "relaton/wmo/docidentifier"
    autoload :Util,          "relaton/wmo/util"
    autoload :Bibliography,  "relaton/wmo/bibliography"
    autoload :Processor,     "relaton/wmo/processor"

    # Returns hash of XML grammar
    # @return [String]
    def self.grammar_hash
      Digest::MD5.hexdigest Relaton::VERSION
    end
  end
end
