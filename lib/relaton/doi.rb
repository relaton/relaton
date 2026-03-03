# frozen_string_literal: true

# require "serrano"
require "relaton/bipm"
# require "relaton_iso_bib"
# require "relaton_w3c"
require "relaton/ietf"
require "relaton/ieee"
require "relaton/nist"
require_relative "doi/version"
require_relative "doi/util"
require_relative "doi/parser"
require_relative "doi/crossref"

# Serrano.configuration do |config|
#   config.mailto = "open.source@ribose.com"
# end

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
