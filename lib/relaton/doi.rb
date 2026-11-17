# frozen_string_literal: true

require_relative "bipm"
require_relative "ietf"
require_relative "ieee"
require_relative "nist"
require_relative "version"
require_relative "doi/util"
require_relative "doi/parser"
require_relative "doi/crossref"
require_relative "doi/http"
require_relative "doi/registration_agency"
require_relative "doi/datacite_parser"
require_relative "doi/datacite"

module Relaton
  module Doi
    extend self

    #
    # Fetch a DOI from the registration agency that holds its metadata
    # (relaton#577): doi.org names the agency, and the DOI goes to that
    # agency's API. A transport failure of the lookup raises
    # Relaton::RequestError, so a DOI is never cached as not found because
    # doi.org did not answer.
    #
    # @param [String, Pubid::Doi::Identifier] doi
    #
    # @return [Bib::ItemData, nil]
    #
    def get(doi)
      case agency = RegistrationAgency.lookup(doi_of(doi))
      when "Crossref" then Crossref.get(doi)
      when "DataCite" then Datacite.get(doi)
      when nil
        Util.info "Not found: doi.org has no registration agency for the DOI.", key: doi.to_s
        nil
      else
        Util.info "Not found: the registration agency #{agency} is not supported.", key: doi.to_s
        nil
      end
    end

    #
    # The DOI itself (`<prefix>/<suffix>`), as the agency APIs take it.
    #
    # A parsed pubid gives it from its components. A String may carry a
    # `doi:` scheme (in any case) or a `doi.org` URL: Relaton::Db keys every
    # form Pubid::Doi reads as one DOI, so all of them must reach the same
    # DOI here, or a miss on one form is cached for the others.
    #
    # @param [String, Pubid::Doi::Identifier] doi
    # @return [String]
    #
    def doi_of(doi)
      return "#{doi.prefix}/#{doi.suffix}" unless doi.is_a?(String)

      doi.sub(%r{\A(?:doi:|https?://(?:dx\.)?doi\.org/)}i, "")
    end

    def grammar_hash
      Digest::MD5.hexdigest Relaton::VERSION
    end
  end
end
