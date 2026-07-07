require "relaton/bib"
require "relaton/index"
require "relaton/version"

# Relaton::Iala is the IALA (International Organization for Marine Aids
# to Navigation) flavor of the unified relaton gem. Adds typed Ext fields
# (urn, webpage, committee, normative, supersedes) so they round-trip
# natively through YAML and XML without per-repo merge hacks.
module Relaton
  module Iala
    INDEXFILE = "index-v2".freeze

    class Error < StandardError; end

    autoload :Util,          "relaton/iala/util"
    autoload :Doctype,       "relaton/iala/doctype"
    autoload :Ext,           "relaton/iala/ext"
    autoload :ItemData,      "relaton/iala/item_data"
    autoload :ItemBase,      "relaton/iala/item_base"
    autoload :Item,          "relaton/iala/item"
    autoload :Relation,      "relaton/iala/relation"
    autoload :Bibitem,       "relaton/iala/bibitem"
    autoload :Bibdata,       "relaton/iala/bibdata"
    autoload :Docidentifier, "relaton/iala/docidentifier"
    autoload :Bibliography,  "relaton/iala/bibliography"
    autoload :Processor,     "relaton/iala/processor"

    # Returns hash of XML grammar
    # @return [String]
    def self.grammar_hash
      Digest::MD5.hexdigest Relaton::VERSION
    end
  end
end
