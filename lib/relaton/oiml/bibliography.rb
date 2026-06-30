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
          # Pass the pubid so Relaton::Index narrows candidates by number via
          # binary search before applying the block. Every row's `:id` is a
          # Pubid::Oiml::Identifier (Relaton::Index deserialized it via the
          # `pubid_class` passed in `#index`), so the block compares pubids and
          # the result picks the latest edition.
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

          item = Relaton::Oiml::Item.from_yaml resp.body
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

        def index
          Relaton::Index.find_or_create(
            :oiml,
            url: "#{ENDPOINT}#{INDEXFILE}.zip",
            file: "#{INDEXFILE}.yaml",
            pubid_class: ::Pubid::Oiml::Identifier,
          )
        end

        # Both `row_id` and `query` are Pubid::Oiml::Identifier instances.
        # Matching is on the year/language-stripped "stem" (e.g. `OIML R 138`),
        # which keeps the type letter and any amendment suffix — so an amendment
        # (`OIML R 138-Amend`) never matches the base record, even though pubid
        # does not expose the suffix as its own attribute. Language must match
        # exactly (a language-less query targets the language-less abstract
        # record); year is nil-tolerant so an unqualified query finds the latest
        # edition (selected by `max_by` in #search). The `year` argument lets a
        # caller pin an edition the reference string omitted.
        def pubid_match?(row_id, query, year)
          wanted_year = (query.year || year)&.to_s
          stem(row_id) == stem(query) &&
            row_id.language.to_s == query.language.to_s &&
            (wanted_year.nil? || row_id.year.to_s == wanted_year)
        end

        # The identifier without its edition year or language, e.g.
        # `OIML R 138:2007 (E)` -> `OIML R 138`. Built from pubid's own model
        # via #exclude (returns a copy, so the cached index id is untouched)
        # rather than string surgery on #to_s. The amendment suffix is kept, so
        # an amendment (`OIML R 138-Amend`) never reduces to the base record.
        def stem(pubid)
          pubid.exclude(:year, :language).to_s
        end
      end
    end
  end
end
