module Relaton
  module Doi
    #
    # Fetch a DataCite-registered DOI from the DataCite REST API
    # (relaton-doi#20). The API is public and needs no key.
    #
    module Datacite
      extend self

      URL = "https://api.datacite.org/dois/%<doi>s".freeze

      #
      # @param [String, Pubid::Doi::Identifier] doi
      #
      # @return [Bib::ItemData, nil]
      #
      def get(doi)
        key = doi.to_s
        Util.info "Fetching from api.datacite.org ...", key: key
        attributes = get_by_id(Doi.doi_of(doi))
        if attributes
          Util.info "Found: `#{attributes['doi']}`", key: key
          DataciteParser.parse attributes
        else
          Util.info "Not found.", key: key
          nil
        end
      end

      #
      # @param [String] id the bare DOI
      #
      # @return [Hash, nil] the record's `attributes`
      #
      def get_by_id(id)
        Http.get_json(format(URL, doi: CGI.escape(id)), "DataCite")&.dig("data", "attributes")
      end
    end
  end
end
