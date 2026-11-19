require "net/http"
require "digest/md5"
require "pubid"
require "moxml"
require_relative "bib"
require_relative "version"
require_relative "core/request_error"
require_relative "arxiv/util"
require_relative "arxiv/parser"
require_relative "arxiv/api"
require_relative "arxiv/bibliography"

module Relaton
  # arXiv e-prints, from the arXiv API (relaton#42).
  module Arxiv
    module_function

    # @return [String]
    def grammar_hash
      Digest::MD5.hexdigest Relaton::VERSION
    end
  end
end
