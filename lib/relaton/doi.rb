# frozen_string_literal: true

require "relaton/bipm"
require "relaton/ietf"
require "relaton/ieee"
require "relaton/nist"
require_relative "doi/version"
require_relative "doi/util"
require_relative "doi/parser"
require_relative "doi/crossref"

module Relaton
  module Doi
    extend self

    def grammar_hash
      Digest::MD5.hexdigest(
        Relaton::Nist::VERSION + Relaton::Ietf::VERSION + Relaton::Ieee::VERSION +
          Relaton::Bipm::VERSION + Relaton::Bib::VERSION,
      )
    end
  end
end
