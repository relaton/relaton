# frozen_string_literal: true

require "relaton/bib"
require "relaton/index"
require "pubid"
require "relaton/version"

# Relaton::Adobe is the Adobe (font tech notes, character collections,
# PostScript Language, etc.) flavor of the unified relaton gem. Adds
# typed Ext fields (urn, webpage, tech_note_number, source_repo_path,
# publication_slug) so they round-trip natively through YAML and XML
# without per-repo merge hacks.
module Relaton
  module Adobe
    INDEXFILE = "index-v2".freeze
    # The machine index on the data repo's Pages site (relaton#206) —
    # manifest + per-shard rows read by the consumer's index; the zip stays
    # on the Pages site for the whole-index retry on a miss.
    PAGES_URL = "https://relaton.github.io/relaton-data-adobe/"

    class Error < StandardError; end

    autoload :Doctype,       "relaton/adobe/doctype"
    autoload :Ext,           "relaton/adobe/ext"
    autoload :ItemData,      "relaton/adobe/item_data"
    autoload :ItemBase,      "relaton/adobe/item_base"
    autoload :Item,          "relaton/adobe/item"
    autoload :Bibitem,       "relaton/adobe/bibitem"
    autoload :Bibdata,       "relaton/adobe/bibdata"
    autoload :Docidentifier, "relaton/adobe/docidentifier"
    autoload :Util,          "relaton/adobe/util"
    autoload :Bibliography,  "relaton/adobe/bibliography"
    autoload :Processor,     "relaton/adobe/processor"

    # Returns hash of XML grammar
    # @return [String]
    def self.grammar_hash
      Digest::MD5.hexdigest Relaton::VERSION
    end
  end
end
