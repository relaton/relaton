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
      bipm_ver = Gem.loaded_specs["relaton-bipm"].version.to_s
      Digest::MD5.hexdigest(
        Relaton::Nist::VERSION + Relaton::Ietf::VERSION + Relaton::Ieee::VERSION +
          bipm_ver + Relaton::Bib::VERSION,
      )
    end
  end
end
