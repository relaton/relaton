# frozen_string_literal: true

require "cgi"
require "json"
require_relative "hit"

module Relaton
  module Itu
    # Page of hit collection.
    #
    # Reference discovery has three sources, because ITU decommissioned the
    # `net4/.../GlobalSearch/RunSearch` endpoint that used to serve all of them:
    #
    # - Recommendations (`ITU-T …`) and ITU-R publications come from the combined
    #   `relaton-data-itu` `index-v2`; an ITU-T reference the index can't serve
    #   falls back to the live `rec.aspx` + `getRecEditions` pair.
    # - Radio Regulations (`ITU-R RR …`) and Operational Bulletins (`… OB.N …`)
    #   are not in the dataset; their landing page URL is derivable from the
    #   reference, so they are resolved directly against `www.itu.int/pub/…`.
    class HitCollection < Relaton::Core::HitCollection
      DOMAIN = "https://www.itu.int"
      GH_ITU = "https://raw.githubusercontent.com/relaton/relaton-data-itu/refs/heads/main/"
      REC_URL = "#{DOMAIN}/ITU-T/recommendations/rec.aspx?rec=%<rec>s&lang=en".freeze
      RECEDITIONS_URL = "#{DOMAIN}/mws/api/recommendations/getRecEditions?idrec=%<idrec>s&lang=en".freeze
      HANDLE_URL = "http://handle.itu.int/11.1002/1000/%<idrec>s-en".freeze

      def search
        case ref.to_ref
        # `ref` is a parsed Pubid, so only the abbreviated `OB.N` form survives
        # here — the local grammar reduces "Operational Bulletin 1096" to the
        # code "Operational" and drops the year, which no route can resolve.
        when %r{^ITU-R\sRR}, %r{\bOB\.} then request_publication
        when /^ITU-T/ then request_recommendation
        when /^ITU-R\s/ then request_document
        end
      rescue Mechanize::ResponseCodeError, SocketError, Timeout::Error, Errno::ECONNRESET,
              EOFError, Net::ProtocolError, OpenSSL::SSL::SSLError => e
        raise Relaton::RequestError, "Could not access #{ref.to_ref}: #{e.message}"
      end

      def agent
        @agent ||= Mechanize.new.tap { |agent| agent.user_agent_alias = "Mac Safari" }
      end

      # Fetch and parse one document from the data repository. Public because
      # `Hit#item` calls it to load an index-derived hit lazily — a reference
      # that matches many editions must not download them all.
      #
      # @param url [String] raw URL of the document's YAML
      # @return [Relaton::Itu::ItemData, nil] nil when the file is missing
      def fetch_item(url)
        resp = agent.get url
        return if resp.code == "404"

        Item.from_yaml(resp.body).tap { |i| i.fetched = Date.today.to_s }
      rescue Mechanize::ResponseCodeError, SocketError, Timeout::Error, Errno::ECONNRESET,
             EOFError, Net::ProtocolError, OpenSSL::SSL::SSLError => e
        # Mechanize *raises* on 404 rather than returning the response, so an
        # index row whose data file has gone missing is caught here —
        # Bibliography then moves on to the next edition instead of failing.
        return if e.is_a?(Mechanize::ResponseCodeError) && e.response_code == "404"

        # `#search` wraps its own failures, but a lazy hit is loaded later, from
        # `Hit#item` — outside that rescue.
        raise Relaton::RequestError, "Could not access #{url}: #{e.message}"
      end

      private

      # ITU-T Recommendations and supplements. The index is preferred (offline,
      # every edition, no scraping); the live path covers what the dataset does
      # not have — Implementers' Guides, the `(V##)`/`Annex` forms the data
      # repo's crawler leaves unindexed, and editions approved since its last
      # crawl. Indexed editions are kept when the live path finds nothing, so a
      # wrong-year reference still reports the years that do exist.
      def request_recommendation
        hits = index_hits
        return @array = hits if year_satisfied? hits

        live = live_hits
        @array = live.empty? ? hits : live
      end

      # @return [Array<Relaton::Itu::Hit>] newest edition first
      def index_hits
        pubid = index_pubid_ref
        return [] unless pubid

        Util.info "Fetching from Relaton repository ...", key: ref.to_s
        index.search(pubid) { |i| index_match?(pubid, i[:id]) }
          .map { |r| index_hit r }.sort_by { |h| edition_key h.hit[:code] }.reverse
      end

      # @param row [Hash] an index row
      # @return [Relaton::Itu::Hit]
      def index_hit(row)
        # `row[:id].to_s` renders the dated docidentifier the data record itself
        # carries ("ITU-T L.163 (11/2018)"), which is what Bibliography's year
        # filtering parses — so no separate edition bookkeeping is needed.
        Hit.new({ code: row[:id].to_s, url: "#{GH_ITU}#{row[:file]}", file: row[:file] }, self)
      end

      # Can the index answer the reference? A year-less reference is satisfied by
      # any hit; a dated one needs the year to be present, otherwise a newer (or
      # unindexed) edition has to come from www.itu.int.
      #
      # @param hits [Array<Relaton::Itu::Hit>]
      # @return [Boolean]
      def year_satisfied?(hits)
        return false if hits.empty?

        ref.year.nil? || hits.any? { |h| edition_key(h.hit[:code]).first == ref.year.to_i }
      end

      # The edition date of a rendered docidentifier, as `[year, month]`. Uses
      # the **first** date in the string, mirroring Bibliography's year filter:
      # an amendment ("ITU-T G.989.2 (2014) Amd 1 (04/2016)") is identified by
      # the year of the recommendation it amends.
      #
      # @param code [String, nil]
      # @return [Array<Integer>]
      def edition_key(code)
        month, year = code.to_s.match(%r{\((?:(\d{2})/)?(\d{4})\)})&.captures
        [year.to_i, month.to_i]
      end

      def index
        Relaton::Index.find_or_create :itu, url: "#{GH_ITU}#{INDEXFILE}.zip",
                                            file: "#{INDEXFILE}.yaml",
                                            pubid_class: ::Pubid::Itu::Identifier
      end

      def request_document # rubocop:todo Metrics/MethodLength, Metrics/AbcSize
        Util.info "Fetching from Relaton repository ...", key: ref.to_s
        # Pass the reference's parsed pubid (not a String) so Relaton::Index can
        # narrow candidates by document number before the block; `index_match?`
        # then matches every edition when the reference omits the part and the
        # exact edition when it names one. Rows are Pubid::Itu objects (not
        # Comparable), so rank by the numeric edition in `code.parts` (`["3"]` → 3)
        # to return the latest — index order isn't by edition.
        pubid = pubid_ref
        row = index.search(pubid) { |i| index_match?(pubid, i[:id]) }
          .max_by { |i| i[:id].code&.parts&.last.to_i }
        return unless row

        url = "#{GH_ITU}#{row[:file]}"
        item = fetch_item url
        return unless item

        hit = Hit.new({ url: url, ref: ref }, self)
        hit.item = item
        @array = [hit]
      end

      # Parse the reference into a Pubid::Itu identifier for the index lookup. A
      # ref pubid can't parse raises (a `Pubid`/`Parslet` error) and propagates to
      # the caller (relaton-cli / API callers rescue it), mirroring the ETSI
      # flavor — the consumer no longer degrades to a raw-string substring search.
      #
      # @return [::Pubid::Itu::Identifier]
      def pubid_ref
        ::Pubid::Itu.parse ref.to_ref
      end

      # The reference as a pubid for an ITU-T index lookup, stripped of its
      # edition date (every edition is a candidate; Bibliography selects the
      # year). Unlike `#pubid_ref` this **rescues** an unparseable reference: the
      # ITU-T path has a live fallback to degrade to, and a malformed reference
      # (e.g. `ITU-T G.Suppl.47`) should warn and report "Not found", not raise.
      #
      # @return [::Pubid::Itu::Identifier, nil]
      def index_pubid_ref
        undated = ref.dup.tap { |r| r.year = r.month = r.day = nil }
        ::Pubid::Itu.parse undated.to_ref
      rescue StandardError
        nil
      end

      # Does an index row's id match the reference? When the reference omits the
      # part/edition (a bare `ITU-R P.838`), every edition of that exact document
      # matches — "search all parts"; when it names a part (`ITU-R P.838-2`), only
      # that edition matches. Delegates to pubid's structured `matches?`, ignoring
      # `:parts` only when the reference omits the part — so a bare `ITU-R M.1`
      # does not match `ITU-R M.10` (a different document number) and `-1` differs
      # from `-10`, without the local `-`-separator anchor. Mirrors the ETSI
      # flavor's `Bibliography#best_match`. Both ids are `Pubid::Itu` identifiers.
      #
      # `:year`/`:month`/`:version` are always ignored because ITU-T rows are one
      # per **edition** (`ITU-T Z.100 (06/2021)`, `ITU-T H.264 (V14) (08/2021)`)
      # while the reference is normalised to the undated form. They are separable
      # trailing components, the same contract ETSI has (`omits: %i[version date]`);
      # Bibliography then picks the requested year and version.
      #
      # @param pubid [::Pubid::Itu::Identifier] the reference
      # @param id [::Pubid::Itu::Identifier] an index row's id
      # @return [Boolean]
      def index_match?(pubid, id)
        ignore = %i[year month version]
        ignore << :parts if pubid.code&.parts.to_a.empty?
        pubid.matches?(id, ignore: ignore)
      end

      # Resolve an ITU-T Recommendation to its editions via the public rec.aspx
      # page (which exposes the record's handle/idrec) and the getRecEditions
      # API. One hit is built per edition, mirroring the multi-result shape the
      # removed RunSearch endpoint returned, so year filtering keeps working.
      #
      # @return [Array<Relaton::Itu::Hit>]
      def live_hits
        Util.info "Fetching from www.itu.int ...", key: ref.to_s
        idrec = fetch_idrec
        return [] unless idrec

        editions(idrec).map { |ed| recommendation_hit ed }
      end

      # @return [String, nil] the record's idrec, or nil when the code is unknown
      def fetch_idrec
        url = format(REC_URL, rec: CGI.escape(rec_query))
        agent.get(url).body[%r{11\.1002/1000/(\d+)}, 1]
      rescue Mechanize::ResponseCodeError => e
        raise unless e.response_code == "404" # unknown code => treat as not found

        nil
      end

      # @return [String] the `rec=` value for the rec.aspx lookup
      def rec_query
        ref.suppl ? "#{ref.code} Suppl. #{ref.suppl}" : ref.code
      end

      # @param idrec [String]
      # @return [Array<Hash>] editions of the recommendation
      def editions(idrec)
        # a `null` body parses to nil, so `|| []` is not redundant
        JSON.parse(agent.get(format(RECEDITIONS_URL, idrec: idrec)).body) || []
      rescue JSON::ParserError
        []
      end

      # @param edition [Hash] a getRecEditions entry
      # @return [Relaton::Itu::Hit]
      def recommendation_hit(edition)
        # No `:ref` key: it drives Hit#gi_imp, which would route an Implementers'
        # Guide reference onto the getImplGuides endpoints.
        Hit.new({
          code: "ITU-T #{edition['rec_name']}",
          title: edition["title"],
          url: format(HANDLE_URL, idrec: edition["idrec"]),
          type: "recommendation",
        }, self)
      end

      # Resolve an ITU-R Radio Regulation or Operational Bulletin to its stable
      # /pub landing page, whose id is derivable from the reference. They are not
      # part of the relaton-data-itu dataset.
      def request_publication
        Util.info "Fetching from www.itu.int ...", key: ref.to_s
        id = ref.year && publication_id
        return @array = [] unless id

        url = "#{DOMAIN}/pub/#{id}"
        page = fetch_publication_page url
        return @array = [] if page.nil? || page.uri.to_s.match?(/notfound/i)

        @array = [Hit.new({ code: publication_code, url: url, type: "publication" }, self)]
      end

      # @return [Mechanize::Page, nil] nil when the publication does not exist
      def fetch_publication_page(url)
        agent.get url
      rescue Mechanize::ResponseCodeError => e
        raise unless e.response_code == "404" # unknown publication => not found

        nil
      end

      # The /pub identifier for a Radio Regulation or an Operational Bulletin
      # (`OB.1096` → `T-SP-OB.1096-2016`). nil — no hit — rather than a bogus URL
      # when the bulletin reference carries no number.
      #
      # @return [String, nil]
      def publication_id
        return "R-REG-RR-#{ref.year}" if ref.code == "RR"

        num = ref.code[/\d+/]
        "T-SP-OB.#{num}-#{ref.year}" if num
      end

      # @return [String] the docidentifier-friendly code (year only, no month)
      def publication_code
        "#{ref.prefix}-#{ref.sector} #{ref.code} (#{ref.year})"
      end
    end
  end
end
