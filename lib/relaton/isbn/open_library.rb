module Relaton
  module Isbn
    #
    # Search ISBN in Openlibrary.
    #
    module OpenLibrary
      extend self

      ENDPOINT = "http://openlibrary.org/api/volumes/brief/isbn/".freeze

      def get(ref, _date = nil, _opts = {}) # rubocop:disable Metrics/MethodLength
        Util.info "Fetching from OpenLibrary ...", key: ref

        isbn = Isbn.new(ref).parse
        unless isbn
          Util.info "Incorrect ISBN.", key: ref
          return
        end

        resp = request_api isbn
        unless resp
          Util.info "Not found.", key: ref
          return
        end

        bib = Parser.parse resp
        Util.info "Found: `#{bib.docidentifier.first.content}`", key: ref
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
