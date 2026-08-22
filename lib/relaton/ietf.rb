# frozen_string_literal: true

require "net/http"
require "relaton/index"
require "relaton/bib"
require_relative "version"
require_relative "ietf/util"
require_relative "ietf/item_data"
require_relative "ietf/item"
require_relative "ietf/bibitem"
require_relative "ietf/bibdata"
require_relative "ietf/rfc/index"
require_relative "ietf/bibliography"

module Relaton
  module Ietf
    # The index the flavor still *reads*: three plain-string `index-v1` files,
    # one per data repo (see Scraper and Processor#remove_index_file). Nothing
    # in this gem writes it any more.
    INDEXFILE = "index-v1".freeze
    # The pubid-structured index `DataFetcher` *writes* (relaton#109). Kept as a
    # second constant rather than bumping INDEXFILE, because producer and
    # consumer migrate separately: the consumer cannot move until an index-v2 is
    # actually published.
    INDEXFILE_V2 = "index-v2".freeze
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
