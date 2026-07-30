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
