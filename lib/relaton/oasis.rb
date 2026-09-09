# frozen_string_literal: true

# Not lazy: DataFetcher names ::Pubid::Oasis::Identifier as the index
# `pubid_class:`, and Docidentifier parses every docid through it.
# (The IANA/IHO/IALA/OGC/ECMA form; spec/relaton/lazy_loading_spec.rb guards
# that this file is not itself loaded when a Db is built.)
require "pubid"
require "relaton/index"
require "relaton/bib"
require_relative "version"
require_relative "oasis/util"
require_relative "oasis/item_data"
require_relative "oasis/item"
require_relative "oasis/bibitem"
require_relative "oasis/bibdata"
require_relative "oasis/bibliography"

module Relaton
  module Oasis
    # The pubid index, both written and read: rows are
    # `Pubid::Oasis::Identifier` hashes (`_type: pubid:oasis:standard`), built
    # and read with `pubid_class: ::Pubid::Oasis::Identifier`.
    #
    # This gem does not produce `index-v1` any more; `relaton-data-oasis`'s
    # crawler derives it from the v2 rows for relaton v2 consumers (the
    # IANA/BIPM/W3C/ECMA shape).
    INDEXFILE = "index-v2".freeze

    class Error < StandardError; end
    # Your code goes here...

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
