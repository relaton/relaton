require "relaton/bib"
require "relaton/index"
require "pubid"
require_relative "oiml/version"
require_relative "oiml/util"
require_relative "oiml/docidentifier"
require_relative "oiml/item"
require_relative "oiml/bibitem"
require_relative "oiml/bibdata"
require_relative "oiml/bibliography"

module Relaton
  module Oiml
    INDEXFILE = "index-v2".freeze

    class Error < StandardError; end

    # Returns hash of XML grammar
    # @return [String]
    def self.grammar_hash
      Digest::MD5.hexdigest Relaton::Oiml::VERSION + Relaton::Bib::VERSION
    end
  end
end
