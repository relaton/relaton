# frozen_string_literal: true

require_relative "bipm"
require_relative "ietf"
require_relative "ieee"
require_relative "nist"
require_relative "version"
require_relative "doi/util"
require_relative "doi/parser"
require_relative "doi/crossref"

module Relaton
  module Doi
    extend self

    def grammar_hash
      Digest::MD5.hexdigest Relaton::VERSION
    end
  end
end
