require "pubid"
require "pubid/w3c"
require "relaton/bib"
require "relaton/index"
require_relative "version"
require_relative "w3c/util"
require_relative "w3c/item"
require_relative "w3c/bibitem"
require_relative "w3c/bibdata"
require_relative "w3c/bibliography"
# Not used by this gem any more; loaded so relaton-data-w3c's crawler can
# require "relaton/w3c" and still reach the legacy index-v1 row shape.
require_relative "w3c/pubid"

module Relaton
  module W3c
    # The runtime index is the pubid-backed `index-v2`, whose rows are
    # `Pubid::W3c::Identifier` leaves serialized as `_type: pubid:w3c:*`, built
    # and read via `pubid_class: ::Pubid::W3c::Identifier`. The bespoke
    # `index-v1` is relaton-v2 legacy and is no longer produced here —
    # `relaton-data-w3c`'s crawler emits it from the retained public
    # `Relaton::W3c::PubId`.
    INDEXFILE = "index-v2".freeze

    class Error < StandardError; end

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
