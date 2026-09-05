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
    # The one index this flavor builds and reads: pubid-keyed rows
    # (`_type: pubid:ecma:*`), via `pubid_class: ::Pubid::Ecma::Identifier`.
    # `relaton-data-ecma`'s crawler derives the legacy `index-v1` from these
    # rows for released consumers, so it is not produced or read here.
    INDEXFILE = "index-v2".freeze

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
