# frozen_string_literal: true

require "relaton/bib"
require "relaton/index"
require "relaton/version"
require "pubid"

# Relaton::Easc is the EASC (Евразийский экономический совет /
# Eurasian Economic Standards Council) flavor of the unified relaton
# gem. Adds typed Ext fields (urn, webpage, session, developer,
# joining_states) so they round-trip natively through YAML and XML
# without per-repo merge hacks.
module Relaton
  module Easc
    INDEXFILE = "index-v2".freeze
    # The machine index on the data repo's Pages site (relaton#206) —
    # manifest + per-shard rows read by the consumer's index; the zip stays
    # on the Pages site for the whole-index retry on a miss.
    PAGES_URL = "https://relaton.github.io/relaton-data-easc/"

    class Error < StandardError; end

    autoload :Doctype,       "relaton/easc/doctype"
    autoload :Ext,           "relaton/easc/ext"
    autoload :ItemData,      "relaton/easc/item_data"
    autoload :ItemBase,      "relaton/easc/item_base"
    autoload :Item,          "relaton/easc/item"
    autoload :Bibitem,       "relaton/easc/bibitem"
    autoload :Bibdata,       "relaton/easc/bibdata"
    autoload :Docidentifier, "relaton/easc/docidentifier"
    autoload :Util,          "relaton/easc/util"
    autoload :Bibliography,  "relaton/easc/bibliography"
    autoload :Processor,     "relaton/easc/processor"

    def self.grammar_hash
      Digest::MD5.hexdigest Relaton::VERSION
    end
  end
end
