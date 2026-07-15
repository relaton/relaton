require "relaton/bib"
require "relaton/index"
require "pubid"
require_relative "version"
require_relative "jcgm/util"
require_relative "jcgm/docidentifier"
require_relative "jcgm/item"
require_relative "jcgm/bibitem"
require_relative "jcgm/bibdata"
require_relative "jcgm/bibliography"

module Relaton
  module Jcgm
    INDEXFILE = "index-v1".freeze

    class Error < StandardError; end

    # Returns hash of XML grammar
    # @return [String]
    def self.grammar_hash
      Digest::MD5.hexdigest Relaton::VERSION
    end
  end
end
