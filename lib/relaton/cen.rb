# frozen_string_literal: true

require "digest/md5"
require "mechanize"
require "relaton/core"
require "isoics"
require "relaton/bib"
require_relative "cen/version"
require_relative "cen/util"
require_relative "cen/model/item"
require_relative "cen/model/bibitem"
require_relative "cen/model/bibdata"
require_relative "cen/scraper"
require_relative "cen/hit_collection"
require_relative "cen/hit"
require_relative "cen/bibliography"

module Relaton
  module Cen
    # Returns hash of XML greammar
    # @return [String]
    def self.grammar_hash
      # gem_path = File.expand_path "..", __dir__
      # grammars_path = File.join gem_path, "grammars", "*"
      # grammars = Dir[grammars_path].sort.map { |gp| File.read gp }.join
      Digest::MD5.hexdigest Cen::VERSION +  Bib::VERSION # grammars
    end
  end
end
