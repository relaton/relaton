# Not lazy: DataFetcher names ::Pubid::Ecma::Identifier as the index
# `pubid_class:`, and Docidentifier parses every docid through it.
# (The IANA/IHO/IALA/OGC form; spec/relaton/lazy_loading_spec.rb guards that
# this file is not itself loaded when a Db is built.)
require "pubid"
require "relaton/index"
require "relaton/bib"
require_relative "version"
require_relative "ecma/util"
require_relative "ecma/item_data"
require_relative "ecma/item"
require_relative "ecma/bibitem"
require_relative "ecma/bibdata"
require_relative "ecma/bibliography"

module Relaton
  module Ecma
    # The index this gem PRODUCES: pubid-keyed rows (`_type: pubid:ecma:*`),
    # built and read with `pubid_class: ::Pubid::Ecma::Identifier`.
    INDEXFILE = "index-v2".freeze

    # TEMPORARY. The consumer (Bibliography) still reads the bespoke v1 index,
    # because `relaton-data-ecma` has not republished yet — `index-v2.zip` is a
    # 404 there today. Delete this constant, and its two call sites in
    # `bibliography.rb` and `processor.rb`, with the consumer migration
    # (HANDOFFS/relaton__relaton__ecma-consume-index-v2.md).
    #
    # This gem no longer PRODUCES v1: `relaton-data-ecma`'s crawler derives it
    # from the v2 rows (the IANA/BIPM/W3C shape), so this is a read-side name,
    # not a second published index.
    INDEXFILE_V1 = "index-v1".freeze

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
