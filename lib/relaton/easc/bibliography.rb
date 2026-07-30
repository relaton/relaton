require "net/http"

module Relaton
  module Easc
    # Index-backed retrieval for the EASC flavor (no scraping). Mirrors
    # Relaton::Oiml::Bibliography: it parses the reference with
    # Pubid::Easc, narrows the pre-built `relaton-data-easc` index by
    # number, fetches the matching per-document YAML over Net::HTTP, and
    # deserializes it into a Relaton::Easc::Item.
    module Bibliography
      ENDPOINT = "https://raw.githubusercontent.com/relaton/relaton-data-easc/main/".freeze

      class << self
        #
        # Search for an EASC publication by its identifier.
        #
        # @param text [String, Pubid::Easc::Identifier] the EASC reference to
        #   look up (e.g. "ПМГ 03-2025", "РМГ 151-2025", or the Latin
        #   transliteration "PMG 03-2025")
        # @param year [String, nil] the edition year (optional; usually embedded
        #   in the reference)
        # @param _opts [Hash] options (unused)
        #
        # @return [Relaton::Easc::Item, nil] the publication or nil if not found
        #
        def search(text, year = nil, _opts = {})
          pubid = text.is_a?(String) ? ::Pubid::Easc.parse(text) : text
          Util.info "Fetching from Relaton repository ...", key: pubid.to_s
          # Pass the pubid so Relaton::Index narrows candidates by number via
          # binary search before applying the block. Every row's `:id` is a
          # Pubid::Easc::Identifier (deserialized via the `pubid_class` passed to
          # #index), so the block compares pubids and picks the latest edition.
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

          item = Relaton::Easc::Item.from_yaml resp.body
          Util.info "Found: `#{item.docidentifier.first&.content}`", key: pubid.to_s
          item.tap { |i| i.fetched = Date.today.to_s }
        rescue SocketError, Errno::EINVAL, Errno::ECONNRESET, EOFError,
               Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError,
               Net::ProtocolError, Net::ReadTimeout, OpenSSL::SSL::SSLError,
               Errno::ETIMEDOUT => e
          raise Relaton::RequestError, "Could not access #{uri}: #{e.message}"
        end

        #
        # Fetch an EASC publication. EASC citations are always dated
        # (e.g. "ПМГ 03-2025"), so there is no undated/most-recent handling to
        # mirror from the ISO/OIML fetchers — `get` just returns what `search`
        # resolves.
        #
        # @see #search
        #
        def get(ref, year = nil, opts = {})
          search(ref, year, opts)
        end

        private

        def index
          Relaton::Index.find_or_create(
            :easc,
            url: "#{ENDPOINT}#{INDEXFILE}.zip",
            file: "#{INDEXFILE}.yaml",
            pubid_class: ::Pubid::Easc::Identifier,
          )
        end

        # Both `row_id` and `query` are Pubid::Easc::Identifier instances. A row
        # matches when its series, defense variant, and number are equal (so a
        # ПМГ never matches a РМГ, and the «В» defense variant never matches the
        # plain series). Year is nil-tolerant: an unqualified query finds the
        # latest edition (selected by `max_by` in #search); the `year` argument
        # lets a caller pin an edition the reference string omitted.
        def pubid_match?(row_id, query, year)
          wanted_year = (query.year || year)&.to_s
          row_id.series == query.series &&
            row_id.variant.to_s == query.variant.to_s &&
            row_id.number.to_s == query.number.to_s &&
            (wanted_year.nil? || row_id.year.to_s == wanted_year)
        end
      end
    end
  end
end
