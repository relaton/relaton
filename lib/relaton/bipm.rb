require "zip"
require "fileutils"
require "parslet"
require "relaton/bib"
require "relaton/index"
require "relaton/core"
require "pubid"
require_relative "version"
require_relative "bipm/util"
require_relative "bipm/id_parser"
require_relative "bipm/item_data"
require_relative "bipm/model/item"
require_relative "bipm/model/bibitem"
require_relative "bipm/model/bibdata"
require_relative "bipm/bibliography"

module Relaton
  module Bipm
    class Error < StandardError; end

    # The runtime index is the pubid-backed `index-v2` (`_type: pubid:bipm:*`).
    # The legacy bespoke `{group,type,number,year}` `index-v1` is still published
    # by `relaton-data-bipm`'s crawler (using the retained `Relaton::Bipm::Id`),
    # but this flavor no longer reads or writes it.
    INDEXFILE = "index-v2".freeze

    # Returns hash of gems versions used to generate the data model.
    # @return [String]
    def grammar_hash
      # gem_path = File.expand_path "..", __dir__
      # grammars_path = File.join gem_path, "grammars", "*"
      # grammars = Dir[grammars_path].sort.map { |gp| File.read gp }.join
      Digest::MD5.hexdigest Relaton::VERSION # grammars
    end

    extend self
  end
end
