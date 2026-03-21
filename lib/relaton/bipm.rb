require "zip"
require "fileutils"
require "parslet"
require "relaton/bib"
require "relaton/index"
require "relaton/core"
require_relative "bipm/version"
require_relative "bipm/util"
require_relative "bipm/item_data"
require_relative "bipm/model/item"
require_relative "bipm/model/bibitem"
require_relative "bipm/model/bibdata"
require_relative "bipm/bibliography"

module Relaton
  module Bipm
    class Error < StandardError; end

    INDEXFILE = "index-v1.yaml".freeze

    # Returns hash of gems versions used to generate the data model.
    # @return [String]
    def grammar_hash
      # gem_path = File.expand_path "..", __dir__
      # grammars_path = File.join gem_path, "grammars", "*"
      # grammars = Dir[grammars_path].sort.map { |gp| File.read gp }.join
      Digest::MD5.hexdigest Relaton::Bipm::VERSION + Relaton::Bib::VERSION # grammars
    end

    extend self
  end
end
