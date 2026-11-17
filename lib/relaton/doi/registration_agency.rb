module Relaton
  module Doi
    #
    # Which registration agency holds a DOI's metadata (relaton#577).
    #
    # Each DOI is registered with one agency, and only that agency's API has
    # its metadata: a DataCite DOI (ResearchGate, Zenodo, data repositories) is
    # a 404 at Crossref. doi.org answers the agency for any DOI.
    #
    module RegistrationAgency
      extend self

      URL = "https://doi.org/ra/%<doi>s".freeze

      #
      # @param [String] doi the bare DOI (`<prefix>/<suffix>`)
      #
      # @return [String, nil] the agency name (`Crossref`, `DataCite`,
      #   `mEDRA`, …), or nil when doi.org has no agency for the DOI
      #   (`DOI does not exist`, `Invalid DOI`)
      #
      # @raise [Relaton::RequestError] when doi.org does not answer
      #
      def lookup(doi)
        answer = Http.get_json format(URL, doi: CGI.escape(doi)), "doi.org"
        Array(answer).first&.dig("RA")
      end
    end
  end
end
