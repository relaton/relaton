require "net/http"

module Relaton
  module Oiml
    module Bibliography
      ENDPOINT = "https://raw.githubusercontent.com/relaton/relaton-data-oiml/main/".freeze

      class << self
        #
        # Search for an OIML publication by its identifier.
        #
        # @param text [String, Pubid::Oiml::Identifier] the OIML reference to
        #   look up (e.g. "OIML R 138" or "OIML R 138:2007 (E)")
        # @param year [String, nil] the edition year (optional; may also be
        #   embedded in the reference)
        # @param _opts [Hash] options (unused)
        #
        # @return [Relaton::Oiml::Item, nil] the publication or nil if not found
        #
        def search(text, year = nil, _opts = {}) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
          pubid = text.is_a?(String) ? ::Pubid::Oiml.parse(text) : text
          Util.info "Fetching from Relaton repository ...", key: pubid.to_s
          row = best_row(pubid, year)
          unless row
            Util.info "Not found.", key: pubid.to_s
            return
          end

          uri = URI("#{ENDPOINT}#{row[:file]}")
          resp = Net::HTTP.get_response uri
          unless resp.code == "200"
            raise Relaton::RequestError, "Could not access #{uri}: HTTP #{resp.code}"
          end

          item = Relaton::Oiml::Item.from_yaml resp.body
          Util.info "Found: `#{item.docidentifier.first&.content}`", key: pubid.to_s
          item.tap { |i| i.fetched = Date.today.to_s }
        rescue SocketError, Errno::EINVAL, Errno::ECONNRESET, EOFError,
               Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError,
               Net::ProtocolError, Net::ReadTimeout, OpenSSL::SSL::SSLError,
               Errno::ETIMEDOUT => e
          raise Relaton::RequestError, "Could not access #{uri}: #{e.message}"
        end

        # Fetch an OIML publication, suppressing the edition year for an undated
        # citation so the designation renders undated (`OIML B 18`), the way the
        # ISO fetcher does. A dated citation (`OIML B 18:2022`, or an explicit
        # `year`) still pins that edition. Mirrors `Relaton::Iso::Bibliography#get`.
        #
        # @param opts [Hash] options
        # @option opts [Boolean] :keep_year retain the edition year even for an
        #   undated citation (or, when false, strip it even for a dated one)
        #
        # @see #search
        def get(ref, year = nil, opts = {})
          item = search(ref, year, opts)
          return item unless item

          pubid = ref.is_a?(String) ? ::Pubid::Oiml.parse(ref) : ref
          dated = oiml_side(pubid).year || year
          # Keep the year only when the citation genuinely asks for it: a resolved
          # year (unless keep_year is explicitly false), or keep_year truthy. (ISO
          # also keeps for :all_parts; OIML has no all-parts retrieval, so search
          # ignores opts and there is nothing to mirror here.)
          return item if (dated && opts[:keep_year].nil?) || opts[:keep_year]

          item.to_most_recent_reference
        end

        private

        def index
          Relaton::Index.find_or_create(
            :oiml,
            url: "#{ENDPOINT}#{INDEXFILE}.zip",
            file: "#{INDEXFILE}.yaml",
            pubid_class: ::Pubid::Oiml::Identifier,
          )
        end

        # The index row for a reference: the latest edition among the rows it
        # matches.
        #
        # The pubid is passed to `Index::Type#search`, so the index narrows
        # candidates by number via binary search, and each row's `:id` is a
        # Pubid::Oiml::Identifier (deserialized via the `pubid_class` in
        # `#index`).
        #
        # A Bulletin matches exactly (`exact: true`). Its year is part of its
        # locator, not an edition: the issue and the sequence render after the
        # year, so the stem below reduces every article of one year to
        # `OIML Bulletin`, and a lookup used to return any one of them.
        #
        # This flavor does not use pubid's subset match `===` yet. Measured
        # over the full `relaton-data-oiml` index, `===` lets a language-less
        # Amendment, Annex or Errata reference reach its translations
        # (`language` is not strict), lets `OIML R 137-1 (F)` reach
        # `OIML R 137-1-2:2012 (F)` (`subpart` is not strict), and rejects
        # `OIML R 102:1995 Annex B-C` for `OIML R 102 Annex B-C` (the
        # `year_on_base` render flag is compared).
        #
        # @param query [Pubid::Oiml::Identifier]
        # @param year [String, nil]
        # @return [Hash, nil] the index row (`{ id:, file: }`)
        def best_row(query, year)
          return index.search(query, exact: true).first if bulletin?(query)

          index.search(query) { |r| pubid_match?(r[:id], query, year) }
               .max_by { |r| oiml_side(r[:id]).year.to_i }
        end

        # @return [Boolean] true for an identifier of an OIML Bulletin
        def bulletin?(pubid)
          pubid.is_a?(::Pubid::Oiml::Identifiers::Bulletin)
        end

        # A document OIML co-publishes with another SDO (ISO confirmed so far)
        # is a Pubid::Oiml::Identifiers::DualPublished — a "|"-joined pair
        # (pubid#437), e.g. `ISO 4064-1:2024|OIML R 49-1:2024`. It delegates
        # #root/#code/#type/#stage/#iteration/#publisher to whichever side is
        # OIML, but NOT #year or #language — those read nil on the wrapper
        # itself regardless of what either side holds. This unwraps to the
        # OIML side for those reads (a plain, non-dual pubid is returned
        # unchanged), so a query and a row agree on year/language/stem
        # whether either one is dual-published or not, and regardless of
        # which side print order named first.
        #
        # @param pubid [Pubid::Oiml::Identifier] a plain or dual-published pubid
        # @return [Pubid::Oiml::Identifier] the OIML-flavored side (itself, for
        #   a plain pubid)
        def oiml_side(pubid)
          pubid.is_a?(::Pubid::Oiml::Identifiers::DualPublished) ? pubid.oiml_identifier : pubid
        end

        # Both `row_id` and `query` are Pubid::Oiml::Identifier instances.
        # Matching is on the year/language-stripped "stem" (e.g. `OIML R 138`),
        # which keeps the type letter and any amendment suffix — so an amendment
        # (`OIML R 138-Amend`) never matches the base record, even though pubid
        # does not expose the suffix as its own attribute. Language must match
        # exactly (a language-less query targets the language-less abstract
        # record); year is nil-tolerant so an unqualified query finds the latest
        # edition (selected by `max_by` in #best_row). The `year` argument lets
        # a caller pin an edition the reference string omitted.
        def pubid_match?(row_id, query, year)
          row = oiml_side(row_id)
          q = oiml_side(query)
          wanted_year = (q.year || year)&.to_s
          stem(row) == stem(q) &&
            row.language.to_s == q.language.to_s &&
            (wanted_year.nil? || row.year.to_s == wanted_year)
        end

        # The identifier without its edition year or language, e.g.
        # `OIML R 138:2007 (E)` -> `OIML R 138`. Built from pubid's own model
        # via #exclude (returns a copy, so the cached index id is untouched)
        # rather than string surgery on #to_s. The amendment suffix is kept, so
        # an amendment (`OIML R 138-Amend`) never reduces to the base record.
        #
        # Reduced through #oiml_side first: `#exclude` recurses correctly into
        # both sides of a DualPublished (unlike a direct #year/#language read),
        # but a plain query has no external side to reduce to, so comparing
        # full dual-published stems against a plain one would never match.
        def stem(pubid)
          oiml_side(pubid).exclude(:year, :language).to_s
        end
      end
    end
  end
end
