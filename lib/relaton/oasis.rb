# frozen_string_literal: true

require "relaton/index"
require "relaton/bib"
require_relative "oasis/version"
require_relative "oasis/util"
require_relative "oasis/item_data"
require_relative "oasis/item"
require_relative "oasis/bibitem"
require_relative "oasis/bibdata"
require_relative "oasis/bibliography"

module Relaton
  module Oasis
    INDEXFILE = "index-v1"
    class Error < StandardError; end
    # Your code goes here...

    # Returns hash of XML reammar
    # @return [String]
    def self.grammar_hash
      # gem_path = File.expand_path "..", __dir__
      # grammars_path = File.join gem_path, "grammars", "*"
      # grammars = Dir[grammars_path].sort.map { |gp| File.read gp }.join
      Digest::MD5.hexdigest Relaton::Oasis::VERSION + Relaton::Bib::VERSION # grammars
    end
  end
end
