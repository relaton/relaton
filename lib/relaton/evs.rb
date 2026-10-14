# frozen_string_literal: true

require "digest/md5"
require "mechanize"
require "relaton/core"
require "isoics"
require "pubid"
require "relaton/bib"
require_relative "version"
require_relative "evs/util"
require_relative "evs/model/item"
require_relative "evs/model/bibitem"
require_relative "evs/model/bibdata"
require_relative "evs/scraper"
require_relative "evs/hit_collection"
require_relative "evs/hit"
require_relative "evs/bibliography"

module Relaton
  module Evs
    # Returns hash of XML grammar
    # @return [String]
    def self.grammar_hash
      Digest::MD5.hexdigest Relaton::VERSION # grammars
    end
  end
end
