require "net/http"

module Relaton
  module Iho
    module Bibliography
      ENDPOINT = "https://raw.githubusercontent.com/relaton/relaton-data-iho/refs/heads/v2/".freeze

      class << self
        #
        # Search for IHO standard by IHO standard Code
        #
        # @param text [String] the IHO standard Code to look up (e..g "IHO B-11")
        #
        # @return [RelatonIho::IhoBibliographicItem, nil] the IHO standard or nil if not found
        #
        def search(text, _year = nil, _opts = {}) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
          pubid = text.is_a?(String) ? ::Pubid::Iho::Identifier.parse(text) : text
          Util.info "Fetching from Relaton repository ...", key: pubid.to_s
          # Pass the pubid so Relaton::Index narrows candidates by number via
          # binary search before applying the block. Every row's `:id` is a
          # Pubid::Iho::Identifiers::* (Relaton::Index deserialized it via the
          # `pubid_class` passed in `#index`), so `pubid_match?` compares pubids.
          row = index.search(pubid) { |r| pubid_match?(r[:id], pubid) }
                     .max_by { |r| recency_key(r[:id]) }
          unless row
            Util.info "Not found.", key: pubid.to_s
            return
          end

          uri = URI("#{ENDPOINT}#{row[:file]}")
          resp = Net::HTTP.get_response uri
          unless resp.code == "200"
            raise Relaton::RequestError, "Could not access #{uri}: HTTP #{resp.code}"
          end

          item = Relaton::Iho::Item.from_yaml resp.body
          enrich_with_pubid(item, pubid)
          Util.info "Found: `#{item.docidentifier.first.content}`", key: pubid.to_s
          item.tap { |i| i.fetched = Date.today.to_s }
        rescue SocketError, Errno::EINVAL, Errno::ECONNRESET, EOFError,
              Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError,
              Net::ProtocolError, Net::ReadTimeout, OpenSSL::SSL::SSLError,
              Errno::ETIMEDOUT => e
          raise Relaton::RequestError, "Could not access #{uri}: #{e.message}"
        end

        # Populate ext.structuredidentifier from the parsed Pubid when the
        # fetched record doesn't already provide one. Maps `pubid.number`
        # (with type prefix, e.g. `S-100`) -> docnumber, `pubid.part` -> part,
        # `pubid.appendix` -> appendixid, `pubid.annex` -> annexid,
        # `pubid.supplement` -> supplementid.
        def enrich_with_pubid(item, pubid)
          return if item.ext&.structuredidentifier&.any?

          sid = StructuredIdentifier.new(
            docnumber: pubid_docnumber(pubid),
            part: pubid.part,
            appendixid: (pubid.appendix if pubid.respond_to?(:appendix)),
            annexid: (pubid.annex if pubid.respond_to?(:annex)),
            supplementid: (pubid.supplement if pubid.respond_to?(:supplement)),
          )
          item.ext ||= Ext.new
          item.ext.structuredidentifier = [sid]
        end

        # "S-100" rather than "100" — keeps the type prefix that distinguishes
        # the IHO series (S/P/M/B/C). Matches spec/fixtures/iho_part.xml.
        def pubid_docnumber(pubid)
          pubid.to_s.sub(/^IHO\s/, "").split(/\s+/, 2).first
        end

        # @param ref [String] the IHO standard Code to look up (e..g "IHO B-11")
        # @param year [String] the year the standard was published (optional)
        #
        # @param opts [Hash] options
        # @option opts [TrueClass, FalseClass] :all_parts restricted to all parts
        #   if all-parts reference is required
        # @option opts [TrueClass, FalseClass] :bibdata
        #
        # @return [RelatonIho::IhoBibliographicItem]
        def get(ref, year = nil, opts = {})
          search(ref, year, opts)
        end

        private

        def index
          # The machine index on the Pages site (relaton#206): a parsed query
          # reads only its own shard; a Pages failure raises
          # `Relaton::RequestError`; the whole-index zip on the same site
          # serves only the retry on a miss.
          Relaton::Index.find_or_create(
            :iho,
            pages_url: PAGES_URL,
            pubid_class: ::Pubid::Iho::Identifier,
          )
        end

        # The sort key for the latest record in a bucket (relaton#407). Each
        # IHO identity carries exactly one trailing discriminator — a dotted
        # `version` (an edition, `B-12 3.0.0`), a series `year` (`P-5 2024`)
        # or a series `volume` with its `issue` (`P-1 Vol. 30 (2)`) — and the
        # key orders by that component, numerically: version segments compare
        # as integers (2.10.0 is later than 2.9.0), as do year, volume and
        # issue. A row with no discriminator at all is the oldest. Rows in
        # one bucket share the discriminator kind once the data is keyed;
        # while kinds coexist the array compare is deterministic, and a
        # year's bare [2024] beats a placeholder edition's [1, 0, 0].
        def recency_key(id)
          if id.year
            [id.year.to_i]
          elsif id.volume
            [id.volume.to_i, id.issue.to_i]
          else
            id.version.to_s.split(".").map(&:to_i)
          end
        end

        # The components that make an IHO document the one it is beyond the
        # series and subdivisions: the edition (`version`), or — for the
        # series identified by year or volume instead (B-7, P-1, P-5, P-6;
        # relaton#407) — the `year` or the `volume`/`issue` pair.
        DISCRIMINATOR_KEYS = %i[version year volume issue].freeze

        # Both `row_id` and `query` are Pubid::Iho::Identifiers::* instances.
        # Class identity pins the series (S/P/M/B/C). Subdivision keys
        # (part/appendix/annex/supplement) use strict equality — a nil query
        # must match a nil row (the umbrella), not an arbitrary subdivision
        # under the same number. That is why this flavor does not use the
        # `===` subset match: pubid reads a nil `part` there as "any part"
        # (pubid's `subset_strict` is not declared for the IHO subdivisions),
        # so `IHO S-100` would answer with a part row.
        #
        # The discriminator keys stay nil-tolerant: an unqualified `IHO B-11`
        # finds the latest edition, an unqualified `IHO P-5` the latest year,
        # and `IHO P-1 Vol. 30` any issue of that volume — while a stated
        # component must match exactly. The comparison runs through pubid's
        # `#exclude` (the primitive `matches?` is built on), so the rules the
        # flavor declares there ride along: excluding `:volume` nils the
        # `issue` with it. `stem_keys` in the BIPM flavor is the same shape.
        def pubid_match?(row_id, query)
          row_id.class == query.class &&
            row_id.exclude(*wildcards(query)) == query.exclude(*wildcards(query))
        end

        # The discriminators the query leaves unset: wildcards for the
        # search, significant whenever the query states one.
        def wildcards(query)
          DISCRIMINATOR_KEYS.select { |key| query.public_send(key).nil? }
        end
      end
    end
  end
end
