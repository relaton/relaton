require "net/http"
require "relaton/bib"
require_relative "version"
require_relative "isbn/util"
require_relative "isbn/isbn"
require_relative "isbn/parser"
require_relative "isbn/open_library"

module Relaton
  module Isbn
    module_function

    # Returns hash of XML reammar
    # @return [String]
    def grammar_hash
      Digest::MD5.hexdigest Relaton::VERSION # grammars
    end
  end
end
