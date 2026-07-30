require "net/http"

module Relaton
  module Adobe
    # Retrieval front-end for the Adobe flavor. Parses a reference with
    # Pubid::Adobe, looks it up in the `relaton-data-adobe` index, fetches the
    # matching YAML record, and deserializes it into a Relaton::Adobe::Item.
    # Modelled on Relaton::Oiml::Bibliography (pubid-backed, index via
    # `pubid_class`); adapted because Adobe identifiers carry no edition
    # year/language, so there is no per-edition selection — each reference maps
    # to a single record.
    module Bibliography
      ENDPOINT = "https://raw.githubusercontent.com/relaton/relaton-data-adobe/main/".freeze

      class << self
        # Search for an Adobe publication by its identifier.
        #
        # @param text [String, Pubid::Adobe::Identifier] the Adobe reference to
        #   look up (e.g. "Adobe Technical Note #5014", "ATN5014",
        #   "Adobe Publication adobe-glyph-list")
        # @param _year [String, nil] unused (Adobe ids carry no edition year)
        # @param _opts [Hash] options (unused)
        # @return [Relaton::Adobe::Item, nil]
        def search(text, _year = nil, _opts = {})
          pubid = pubid_for(text) or return
          Util.info "Fetching from Relaton repository ...", key: pubid.to_s
          # Tech notes narrow by number via binary search; publications have no
          # number, so pass nil to scan (Relaton::Index::Type#search returns all
          # rows for a nil id, then applies the block).
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

          item = Relaton::Adobe::Item.from_yaml resp.body
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

        # Coerce a reference to a Pubid::Adobe identifier. A non-canonical or
        # non-Adobe string (e.g. a title-cased "Adobe Glyph List") is a graceful
        # miss (logged, returns nil) rather than a raised Parslet error — the
        # ref reached here only because it matched the flavor's prefix regex.
        def pubid_for(text)
          return text unless text.is_a?(String)

          ::Pubid::Adobe.parse(text)
        rescue StandardError
          Util.info "Not found.", key: text
          nil
        end

        def index
          Relaton::Index.find_or_create(
            :adobe,
            url: "#{ENDPOINT}#{INDEXFILE}.zip",
            file: "#{INDEXFILE}.yaml",
            pubid_class: ::Pubid::Adobe::Identifier,
          )
        end

        # Identity match on the human render: pubid renders a tech note as
        # `Adobe TN <n>` (dropping the filename slug, so `ATN5014` and
        # `Adobe Technical Note #5014` both match a record stored with its slug)
        # and a publication as `Adobe Publication <slug>` including its version.
        # Both `row_id` and `query` are Pubid::Adobe identifiers.
        def pubid_match?(row_id, query)
          row_id.to_s == query.to_s
        end
      end
    end
  end
end
