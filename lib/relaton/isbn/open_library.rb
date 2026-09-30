module Relaton
  module Isbn
    #
    # Search ISBN in Openlibrary.
    #
    module OpenLibrary
      extend self

      ENDPOINT = "http://openlibrary.org/api/volumes/brief/isbn/".freeze

      # @param ref [String, Pubid::Isbn::Identifier] an ISBN-10 or ISBN-13
      # @return [Relaton::Bib::ItemData, nil]
      def get(ref, _date = nil, _opts = {}) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
        Util.info "Fetching from OpenLibrary ...", key: ref.to_s

        # A parsed pubid gives its digits (`raw`); `Isbn#parse` validates them
        # and converts an ISBN-10 to ISBN-13, as for a String.
        isbn = Isbn.new(ref.is_a?(String) ? ref : ref.raw).parse
        unless isbn
          Util.info "Incorrect ISBN.", key: ref.to_s
          return
        end

        resp = request_api isbn
        unless resp
          Util.info "Not found.", key: ref.to_s
          return
        end

        bib = Parser.parse resp
        Util.info "Found: `#{bib.docidentifier.first.content}`", key: ref.to_s
        bib
      end

      def request_api(isbn)
        uri = URI "#{ENDPOINT}#{isbn}.json"
        response = Net::HTTP.get_response uri
        return unless response.is_a? Net::HTTPSuccess

        data = JSON.parse response.body
        return unless data["records"]&.any?

        data["records"].first.last
      end
    end
  end
end
