require "relaton/bib"
require "relaton/index"
require_relative "version"
require_relative "iala/util"
require_relative "iala/docidentifier"
require_relative "iala/item"
require_relative "iala/bibitem"
require_relative "iala/bibdata"
require_relative "iala/bibliography"

module Relaton
  module Iala
    INDEXFILE = "index-v2".freeze

    class Error < StandardError; end

    # Returns hash of XML grammar
    # @return [String]
    def self.grammar_hash
      Digest::MD5.hexdigest Relaton::VERSION
    end
  end
end
