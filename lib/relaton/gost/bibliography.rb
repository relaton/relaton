require "net/http"

module Relaton
  module Gost
    # Retrieval front-end for the GOST flavor. Parses the citation with
    # Pubid::Gost, looks it up in the pubid-structured `relaton-data-gost`
    # index-v2, and fetches the matching per-document YAML over HTTP.
    #
    # The index rows are keyed by Pubid::Gost identifiers (`_type: pubid:gost:
    # {interstate,national}-standard`, number, year), so `Relaton::Index`
    # narrows candidates by number via binary search before the block applies
    # the precise pubid match. Both Latin "GOST"/"GOST R" and Cyrillic
    # "ГОСТ"/"ГОСТ Р" surface forms parse (Pubid normalises Cyrillic to Latin).
    module Bibliography
      ENDPOINT = "https://raw.githubusercontent.com/relaton/relaton-data-gost/main/".freeze

      class << self
        # Search for a GOST publication by its identifier.
        #
        # @param text [String, Pubid::Gost::Identifier] the GOST reference to
        #   look up (e.g. "GOST R 34.12-2015", "GOST 14946-82", "ГОСТ 1.0")
        # @param year [String, nil] the edition year (optional; may also be
        #   embedded in the reference)
        # @param _opts [Hash] options (unused)
        # @return [Relaton::Gost::Item, nil]
        def search(text, year = nil, _opts = {})
          pubid = text.is_a?(String) ? ::Pubid::Gost.parse(text) : text
          Util.info "Fetching from Relaton repository ...", key: pubid.to_s
          # Pass the pubid so Relaton::Index narrows candidates by number via
          # binary search before applying the block; pick the latest edition
          # for an undated citation.
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

          item = Relaton::Gost::Item.from_yaml resp.body
          Util.info "Found: `#{item.docidentifier.first&.content}`", key: pubid.to_s
          item.tap { |i| i.fetched = Date.today.to_s }
        rescue SocketError, Errno::EINVAL, Errno::ECONNRESET, EOFError,
               Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError,
               Net::ProtocolError, Net::ReadTimeout, OpenSSL::SSL::SSLError,
               Errno::ETIMEDOUT => e
          raise Relaton::RequestError, "Could not access #{uri}: #{e.message}"
        end

        # Fetch a GOST publication, suppressing the edition year for an undated
        # citation so the designation renders undated (`GOST R 34.12`), the way
        # the ISO/OIML fetchers do. A dated citation (`GOST R 34.12-2015`, or an
        # explicit `year`) still pins that edition.
        #
        # @param opts [Hash] options
        # @option opts [Boolean] :keep_year retain the edition year even for an
        #   undated citation (or, when false, strip it even for a dated one)
        # @see #search
        def get(ref, year = nil, opts = {})
          item = search(ref, year, opts)
          return item unless item

          pubid = ref.is_a?(String) ? ::Pubid::Gost.parse(ref) : ref
          dated = pubid.year || year
          return item if (dated && opts[:keep_year].nil?) || opts[:keep_year]

          item.to_most_recent_reference
        end

        private

        def index
          Relaton::Index.find_or_create(
            :gost,
            url: "#{ENDPOINT}#{INDEXFILE}.zip",
            file: "#{INDEXFILE}.yaml",
            pubid_class: ::Pubid::Gost::Identifier,
          )
        end

        # Both `row_id` and `query` are Pubid::Gost identifiers. Match on the
        # concrete subtype (interstate vs national — same number is a different
        # document across the two) and the base number; year is nil-tolerant so
        # an unqualified query finds the latest edition (selected by `max_by` in
        # #search). The `year` argument lets a caller pin an edition the
        # reference string omitted. (GOST pubid `matches?`/`exclude(:year)` do
        # not support the nil-year-matches-any semantics, so this is explicit.)
        def pubid_match?(row_id, query, year)
          wanted_year = (query.year || year)&.to_s
          row_id.class == query.class &&
            row_id.root.number.to_s == query.root.number.to_s &&
            (wanted_year.nil? || row_id.year.to_s == wanted_year)
        end
      end
    end
  end
end
