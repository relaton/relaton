require "net/http"
require "uri"
require "relaton/index"
require "relaton/iso"
require_relative "plateau/version"
require_relative "plateau/util"
# require_relative "plateau/docidentifier"
# require_relative "plateau/document_type"
require_relative "plateau/item"
require_relative "plateau/bibitem"
require_relative "plateau/bibdata"
# require_relative "plateau/hit"
# require_relative "plateau/bibliography"
# require_relative "plateau/xml_parser"
# require_relative "plateau/hash_converter"
# require_relative "plateau/fetcher"

module Relaton
  module Plateau
    class Error < StandardError; end

    def self.grammar_hash
      Digest::MD5.hexdigest Relaton::Plateau::VERSION + Relaton::Bib::VERSION # grammars
    end
  end
end
