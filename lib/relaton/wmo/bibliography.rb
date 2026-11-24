require "net/http"

module Relaton
  module Wmo
    # Retrieval front-end for the WMO flavor. Parses a reference with
    # Pubid::Wmo, looks it up in the `relaton-data-wmo` index, fetches the
    # matching YAML record, and deserializes it into a Relaton::Wmo::Item.
    # Modelled on Relaton::Adobe::Bibliography (pubid-backed, index via
    # `pubid_class`); WMO identifiers carry no edition year, so each
    # reference maps to a single record.
    module Bibliography
      ENDPOINT = "https://raw.githubusercontent.com/relaton/relaton-data-wmo/main/".freeze

      class << self
        # Search for a WMO publication by its identifier.
        #
        # @param text [String, Pubid::Wmo::Identifier] the WMO reference
        #   (e.g. "WMO-No. 8", "WMO/TD-No. 1551", "GAW Report No. 234")
        # @param _year [String, nil] unused (WMO ids carry no edition year)
        # @param _opts [Hash] options (unused)
        # @return [Relaton::Wmo::Item, nil]
        def search(text, _year = nil, _opts = {})
          pubid = pubid_for(text) or return
          Util.info "Fetching from Relaton repository ...", key: pubid.to_s
          # Numbered series narrow via binary search; series with no
          # number pass nil to scan (Relaton::Index::Type#search returns
          # all rows for a nil id, then applies the block).
          query = pubid.root.number ? pubid : nil
          row = index.search(query) { |r| pubid_match?(r[:id], pubid) }.first
          unless row
            Util.info "Not found.", key: pubid.to_s
            return
          end

          uri = URI("#{ENDPOINT}#{row[:file]}")
          resp = Net::HTTP.get_response uri
          unless resp.code == "200"
            raise Relaton::RequestError, "Could not access #{uri}: HTTP #{resp.code}"
          end

          item = Relaton::Wmo::Item.from_yaml resp.body
          Util.info "Found: `#{item.docidentifier.first&.content}`", key: pubid.to_s
          item.tap { |i| i.fetched = Date.today.to_s }
        rescue SocketError, Errno::EINVAL, Errno::ECONNRESET, EOFError,
               Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError,
               Net::ProtocolError, Net::ReadTimeout, OpenSSL::SSL::SSLError,
               Errno::ETIMEDOUT => e
          raise Relaton::RequestError, "Could not access #{uri}: #{e.message}"
        end

        def get(ref, year = nil, opts = {})
          search(ref, year, opts)
        end

        private

        # Coerce a reference to a Pubid::Wmo identifier. A non-canonical
        # string is a graceful miss (logged, returns nil) rather than a
        # raised Parslet error — the ref reached here only because it
        # matched the flavor's prefix regex.
        def pubid_for(text)
          return text unless text.is_a?(String)

          ::Pubid::Wmo.parse(text)
        rescue StandardError
          Util.info "Not found.", key: text
          nil
        end

        def index
          Relaton::Index.find_or_create(
            :wmo,
            pages_url: PAGES_URL,
            pubid_class: ::Pubid::Wmo::Identifier,
          )
        end

        # Identity match on the human render: both `row_id` and `query`
        # are Pubid::Wmo identifiers rendering to their canonical forms.
        def pubid_match?(row_id, query)
          row_id.to_s == query.to_s
        end
      end
    end
  end
end
