# frozen_string_literal: true

require "faraday"
require "relaton/index"
require "pubid"
require "relaton/bib"
require_relative "version"
require_relative "iana/util"
require_relative "iana/item_data"
require_relative "iana/item"
require_relative "iana/bibitem"
require_relative "iana/bibdata"
require_relative "iana/bibliography"
# require_relative "relaton_iana/parser"
# require_relative "relaton_iana/data_fetcher"

module Relaton
  module Iana
    # The runtime index is the pubid-backed `index-v2`, whose rows are
    # `Pubid::Iana::Identifiers::Registry` identifiers serialized as
    # `_type: pubid:iana:registry` with `number` (the TOP-LEVEL registry slug)
    # and an optional `sub_registry` — built and read via
    # `pubid_class: ::Pubid::Iana::Identifier`.
    #
    # The legacy string-keyed `index-v1` (whose `:id` was the bare
    # `registry[/sub-registry]` slug) is no longer produced or read here; it is
    # emitted by `relaton-data-iana`'s own `crawler.rb`, derived from `index-v2`,
    # so released gem lines keep resolving. See lib/relaton/iana/CLAUDE.md.
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
