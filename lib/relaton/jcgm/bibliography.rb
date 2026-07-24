require "net/http"

module Relaton
  module Jcgm
    # Retrieval for JCGM (Joint Committee for Guides in Metrology) publications.
    # Index-backed (no scraping): the reference is parsed with `Pubid::Jcgm`,
    # matched against the pre-built index (whose rows are `Pubid::Jcgm::Identifier`
    # hashes, deserialized via `pubid_class`), and the matching per-document YAML
    # is fetched from the `relaton/relaton-data-jcgm` GitHub repo.
    module Bibliography
      ENDPOINT = "https://raw.githubusercontent.com/relaton/relaton-data-jcgm/main/".freeze

      class << self
        #
        # Search for a JCGM publication by its identifier.
        #
        # @param text [String, Pubid::Jcgm::Identifier] e.g. "JCGM 200:2012" or
        #   "JCGM 17th Meeting (2012)"
        # @param year [String, nil] edition year (optional; may be embedded)
        # @param _opts [Hash] options (unused)
        #
        # @return [Relaton::Jcgm::Item, nil]
        #
        def search(text, year = nil, _opts = {}) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
          pubid = parse_ref(text)
          # A malformed reference the pubid grammar rejects is a graceful miss,
          # not a Parslet::ParseFailed raised to the caller.
          return unless pubid

          Util.info "Fetching from Relaton repository ...", key: pubid.to_s
          row = index.search(pubid) { |r| pubid_match?(r[:id], pubid, year) }
                     .max_by { |r| r[:id].year.to_i }
          unless row
            Util.info "Not found.", key: pubid.to_s
            return
          end

          uri = URI("#{ENDPOINT}#{row[:file]}")
          resp = Net::HTTP.get_response uri
          unless resp.code == "200"
            raise Relaton::RequestError, "Could not access #{uri}: HTTP #{resp.code}"
          end

          item = Relaton::Jcgm::Item.from_yaml resp.body
          Util.info "Found: `#{item.docidentifier.first&.content}`", key: pubid.to_s
          item.tap { |i| i.fetched = Date.today.to_s }
        rescue SocketError, Errno::EINVAL, Errno::ECONNRESET, EOFError,
               Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError,
               Net::ProtocolError, Net::ReadTimeout, OpenSSL::SSL::SSLError,
               Errno::ETIMEDOUT => e
          raise Relaton::RequestError, "Could not access #{uri}: #{e.message}"
        end

        # @see #search
        def get(ref, year = nil, opts = {})
          search(ref, year, opts)
        end

        private

        # Parse a reference into a Pubid::Jcgm identifier, returning nil (a
        # graceful "not found") rather than raising if the grammar rejects it.
        def parse_ref(text)
          return text unless text.is_a?(String)

          ::Pubid::Jcgm.parse(text)
        rescue StandardError => e
          Util.info "Unsupported JCGM reference: #{e.message}", key: text
          nil
        end

        def index
          Relaton::Index.find_or_create(
            :jcgm,
            url: "#{ENDPOINT}#{INDEXFILE}.zip",
            file: "#{INDEXFILE}.yaml",
            pubid_class: ::Pubid::Jcgm::Identifier,
          )
        end

        # `row_id` and `query` are both `Pubid::Jcgm::Identifier` instances.
        # Matching is on the year-stripped "stem": guides distinguish editions by
        # year (`JCGM 200:2008` vs `:2012`), so the year is excluded from the stem
        # and the latest edition is picked by `max_by` in #search. Meetings
        # distinguish by number (`17th` vs `18th`), which stays in the stem, so
        # they never collapse together. The type is inherent to the pubid string,
        # so cross-type collisions cannot occur. `year` lets a caller pin an
        # edition the reference string omitted.
        def pubid_match?(row_id, query, year)
          wanted_year = (query.year || year)&.to_s
          stem(row_id) == stem(query) &&
            (wanted_year.nil? || row_id.year.to_s == wanted_year)
        end

        # The identifier without its edition year, via pubid's own model
        # (`#exclude` returns a copy, so the cached index id is untouched). Falls
        # back to the full string if `exclude` isn't supported for the type.
        def stem(pubid)
          pubid.exclude(:year).to_s
        rescue StandardError
          pubid.to_s
        end
      end
    end
  end
end
