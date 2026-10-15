# frozen_string_literal: true

require "net/http"
require "pubid"
require "relaton/index"
require "isoics"
require "relaton/bib"
require "relaton/core"
require_relative "version"
require_relative "iso/util"
require_relative "iso/item_data"
require_relative "iso/model/item"
require_relative "iso/model/relation"
require_relative "iso/model/bibitem"
require_relative "iso/model/bibdata"
require_relative "iso/hit_collection"
require_relative "iso/bibliography"

module Relaton
  module Iso
    INDEXFILE = "index-v2"
    # The machine index on the data repo's Pages site (relaton#206) —
    # manifest + per-shard rows read by HitCollection's index; the zip stays
    # on the Pages site for the whole-index retry on a miss.
    PAGES_URL = "https://relaton.github.io/relaton-data-iso/"

    def self.grammar_hash
      # gem_path = File.expand_path "..", __dir__
      # grammars_path = File.join gem_path, "grammars", "*"
      # grammars = Dir[grammars_path].sort.map { |gp| File.read gp, encoding: "UTF-8" }.join
      Digest::MD5.hexdigest Relaton::VERSION # grammars
    end
  end
end
