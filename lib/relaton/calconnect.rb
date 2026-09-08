# Not lazy: DataFetcher names ::Pubid::Calconnect::Identifier as the index
# `pubid_class:`, and Docidentifier parses every docid through it.
# (The ECMA/IANA/IHO/OGC form; spec/relaton/lazy_loading_spec.rb guards that
# this file is not itself loaded when a Db is built.)
require "pubid"
require "relaton/index"
require "relaton/core"
require_relative "version"
require_relative "calconnect/model/item"
require_relative "calconnect/util"
require_relative "calconnect/model/bibitem"
require_relative "calconnect/model/bibdata"
require_relative "calconnect/bibliography"
require_relative "calconnect/hit_collection"
require_relative "calconnect/hit"
require_relative "calconnect/scraper"

module Relaton
  module Calconnect
    # The index this flavor BUILDS: pubid-keyed rows
    # (`_type: pubid:calconnect:standard`), via
    # `pubid_class: ::Pubid::Calconnect::Identifier`.
    INDEXFILE = "index-v2".freeze

    # The index this flavor still READS. Temporary, and a read-side name only —
    # not a second published index. `relaton-data-calconnect` publishes no
    # `index-v2.zip` yet, so the runtime keeps reading the legacy v1 until it
    # does. The consumer commit points the read path at INDEXFILE and deletes
    # this constant. See lib/relaton/calconnect/CLAUDE.md.
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
