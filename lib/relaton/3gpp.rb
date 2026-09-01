require "net/http"
# Not lazy: Processor#remove_index_file names ::Pubid::Tgpp::Identifier on the
# cold path reached by Db#clear, which never loads Bibliography.
# (spec/relaton/lazy_loading_spec.rb guards this; the IANA/IHO/IALA form.)
require "pubid"
require "relaton/index"
require "relaton/core"
require "relaton/bib"
require_relative "version"
require_relative "3gpp/util"
require_relative "3gpp/item"
require_relative "3gpp/bibitem"
require_relative "3gpp/bibdata"
require_relative "3gpp/bibliography"

module Relaton
  module ThreeGpp
    INDEXFILE = "index-v2".freeze

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
