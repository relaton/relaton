# frozen_string_literal: true

require "json"
require_relative "family_cache"

module Relaton
  module Itu
    # Shared extraction of ITU-T Recommendation metadata from the
    # `mws/api/recommendations/*` detail endpoints. Reused by BOTH the live
    # lookup path (`RecommendationParser`, via `Scraper`) and the offline
    # harvester (`DataParserT`), so producer output and runtime output stay
    # identical field-for-field.
    #
    # The includer must provide four hooks:
    #   #agent — a Mechanize agent (browser UA; www.itu.int is behind an F5 WAF)
    #   #idrec — the recommendation record id
    #   #imp   — whether this is an Implementers' Guide (live-only; harvester false)
    #   #cache — a cross-row cache, defaulting to NullCache (see below)
    #
    # `#doc` (the getRecHdrDetail JSON) is memoised here from those hooks.
    #
    # **The cache and the runtime boundary.** `searchRecs` returns one row per
    # *edition*, but two of the four endpoints below answer for the whole
    # recommendation, so the offline harvester asks the same question once per
    # edition — 21 times over for H.264. `#cache` lets it ask once instead. The
    # live lookup path handles one recommendation per `Bibliography.get` and must
    # not share state between calls, so the default is {NullCache}, whose
    # `#fetch` is a bare yield: same behaviour, same requests, nothing retained.
    # `Scraper` is deliberately left calling the three-argument constructor, so
    # no path from `Bibliography.get` can reach a real cache.
    module RecommendationFields
      include Relaton::Core::ArrayWrapper

      RECHDR = "https://www.itu.int/mws/api/recommendations/getRecHdrDetail?idrec=%{idrec}&lang=en"
      RECEDITIONS = "https://www.itu.int/mws/api/recommendations/getRecEditions?idrec=%{idrec}&lang=en"
      RECSUPPLEMENTS = "https://www.itu.int/mws/api/recommendations/getRecSupplements?idrec=%{idrec}&lang=en"
      IMPLGUIDES = "https://www.itu.int/mws/api/recommendations/getImplGuides?idrec=%{idrec}&lang=en"

      # The recommendation header detail (getRecHdrDetail / getImplGuides).
      # @return [Hash]
      def doc
        @doc ||= begin
          url = (imp ? IMPLGUIDES : RECHDR) % { idrec: idrec }
          resp = get_data url
          imp ? resp.first : resp
        end
      end

      # Cross-row cache for the family-invariant endpoints. Overridden by
      # RecommendationParser when the harvester passes one in.
      # @return [#fetch, #warm]
      def cache
        NullCache.instance
      end

      # Canonical id for the recommendation this edition belongs to: the
      # smallest idrec ITU's own getRecEditions response lists.
      #
      # Derived from API output, never from parsing `rec_name`. That is the
      # whole point — two recommendations whose names happen to normalize alike
      # would silently share each other's metadata, and nothing downstream would
      # notice (the data repo's `guard_enrichment` counts `contributor:` lines,
      # which such a record still has).
      #
      # Free on the live path: `Scraper#parse_page` already calls
      # `#fetch_relations`, which already calls `#editions`.
      #
      # @return [Integer, String]
      def family_id
        @family_id ||= (editions.filter_map { |e| e["idrec"] }.min || idrec)
      end

      # @return [String, nil]
      def fetch_edition
        self_edition&.dig("Version")
      end

      # @return [Array<Relaton::Bib::Title>]
      def fetch_titles
        title = imp ? doc["imp_title_e"] : doc["rec_title"]
        return [] if title.nil? || title.empty?

        Relaton::Bib::Title.from_string title, "en", "Latn"
      end

      # @return [Relaton::Bib::Status, nil]
      def fetch_status
        inforce = imp ? imp_status : doc["status"]
        return if inforce.nil? || inforce.empty?

        status = inforce == "In force" ? "Published" : "Withdrawal"
        Relaton::Bib::Status.new(stage: Relaton::Bib::Status::Stage.new(content: status))
      end

      # @return [Array<Relaton::Bib::Date>]
      def fetch_dates
        array(doc_date).map { |on| Relaton::Bib::Date.new(type: "published", at: on) }
      end

      # @return [Array<Relaton::Bib::Abstract>]
      def fetch_abstract
        array(doc["summary"]).map do |content|
          Relaton::Bib::Abstract.new(content: content, language: "en", script: "Latn")
        end
      end

      # @return [Array<Relaton::Bib::Uri>]
      def fetch_source
        link = imp ? doc["imp_dms_link"] : doc["handle_id"]
        links = [Relaton::Bib::Uri.new(type: "src", content: link)]
        links << Relaton::Bib::Uri.new(type: "pdf", content: doc["handle_id_pdf_link"]) if doc["handle_id_pdf_link"]
        imp_word_link { |wlink| links << Relaton::Bib::Uri.new(type: "word", content: wlink) }
        links
      end

      def doc_date
        return @doc_date if defined? @doc_date

        date = imp ? doc["imp_approval_date"] : doc["approval_date"]
        @doc_date = Date.parse(date).to_s rescue date # rubocop:disable Style/RescueModifier
      end

      # @return [Array<Relaton::Bib::Relation>]
      def fetch_relations
        relations = []
        editions.each do |ed|
          next if ed["idrec"] == idrec

          relations << create_relation("hasEdition", ed["title"], ed["rec_name"])
        end

        supplements.each { |supp| relations << create_relation("complementOf", supp["title_text"], supp["rec_name"]) }
        relations
      end

      # The equivalent ISO/IEC(/IEEE) identifier, from the recommendation
      # header's `iso_number` (e.g. "ISO/IEC 17788:2014 (Common)", or a deliverable
      # form like "ISO/IEC TR 29110"). Used as an additional docidentifier. Only
      # recommendations carry it. The optional TR/TS/PAS/IWA/Guide token keeps
      # deliverable forms that a bare `\d` anchor would drop.
      # @return [Relaton::Itu::Docidentifier, nil]
      def iso_docid
        num = doc["iso_number"]
        id = num && num[%r{ISO(?:/IEC)?(?:/IEEE)?(?:\s+(?:TR|TS|PAS|IWA|Guide))?\s+\d[\d-]*}]
        Docidentifier.new(type: "ISO", content: id, primary: true) if id
      end

      # The editorial-group (study group / TSAG) contributor, from the
      # recommendation HTML page's workgroup name.
      # @param bureau [String, nil] the sector letter, e.g. "T" (from ITU-T)
      # @return [Relaton::Bib::Contributor, nil]
      def editorial_group(bureau)
        return unless bureau

        org = Relaton::Bib::Organization.new(
          name: [Relaton::Bib::TypedLocalizedString.new(content: "International Telecommunication Union")],
          abbreviation: Relaton::Bib::LocalizedString.new(content: "ITU-#{bureau.upcase}"),
          subdivision: group_subdivision(fetch_workgroup),
        )
        role = Relaton::Bib::Contributor::Role.new(
          type: "author",
          description: [Relaton::Bib::LocalizedMarkedUpString.new(content: "committee")],
        )
        Relaton::Bib::Contributor.new(organization: org, role: [role])
      end

      # The publisher contributor (ITU) for the given abbreviation.
      # @param abbrev [String, nil] e.g. "ITU"
      # @return [Relaton::Bib::Contributor, nil]
      def publisher(abbrev)
        return unless abbrev == "ITU"

        org = Relaton::Bib::Organization.new(
          name: [Relaton::Bib::TypedLocalizedString.new(content: "International Telecommunication Union")],
          abbreviation: Relaton::Bib::LocalizedString.new(content: abbrev),
          uri: [Relaton::Bib::Uri.new(content: "www.itu.int")],
        )
        role = Relaton::Bib::Contributor::Role.new(type: "publisher")
        Relaton::Bib::Contributor.new(organization: org, role: [role])
      end

      # @param wg_name [String, nil]
      # @return [Array<Relaton::Bib::Subdivision>]
      def group_subdivision(wg_name)
        return [] unless wg_name

        subtype = case wg_name
                  when /Advisory Group/ then "tsag"
                  when /Study Group/ then "study-group"
                  else "work-group"
                  end
        [Relaton::Bib::Subdivision.new(
          type: "technical-committee",
          subtype: subtype,
          name: [Relaton::Bib::TypedLocalizedString.new(content: wg_name)],
        )]
      end

      # Fetch the study group name from the recommendation HTML page.
      #
      # The single most expensive request per record: `rec.aspx` is ~90-240 KB
      # of HTML that then has to be parsed into a DOM. It is also the one field
      # here that is a property of the *recommendation* rather than the edition
      # — ITU renders the current owning study group even on an old edition's
      # page, which is why `?rec=H.264` and `?rec=14659` both yield "ITU-T Study
      # Group 21" in `spec/itu/vcr_cassettes/itu_t_h_264.yml`. So it is cached
      # per family.
      #
      # The rescue sits outside the cache on purpose: a transient failure must
      # not be stored as nil for the whole family. FamilyCache does not mark an
      # entry computed when the block raises, so the next sibling retries.
      # @return [String, nil]
      def fetch_workgroup
        # Short-circuited rather than keyed-then-yielded, because #family_id
        # reads #editions: with the null cache that would add a getRecEditions
        # request to a runtime lookup that did not need one. The live path must
        # keep exactly the request count it had.
        return workgroup_from_page unless cache.caching?

        cache.fetch([:workgroup, family_id]) { workgroup_from_page }
      rescue StandardError
        nil
      end

      private

      def workgroup_from_page
        url = "https://www.itu.int/ITU-T/recommendations/rec.aspx?rec=#{idrec}&lang=en"
        page = agent.get(url)
        wg = page.at('//span[contains(@id, "uc_rec_main_info1_rpt_main_ctl00_Label8")]/a')
        wg&.text
      end

      def fetch_editions
        get_data(RECEDITIONS % { idrec: idrec }) || []
      end

      # The other editions this response answers for.
      #
      # Empty unless the response actually lists the idrec we asked for: if it
      # does not, the endpoint's contract has changed under us and sharing the
      # payload would hand a whole family another recommendation's data. Losing
      # the dedup is the cheap failure; sharing wrongly is the expensive one.
      def siblings_of(rows)
        unless rows.any? { |r| r["idrec"] == idrec }
          Util.warn "ITU-T: getRecEditions(#{idrec}) does not list #{idrec}; not sharing it across the family"
          return []
        end

        rows.filter_map { |r| [:editions, r["idrec"]] unless r["idrec"] == idrec }
      end

      def get_data(url)
        JSON.parse request_document(url).body
      end

      def request_document(url)
        agent.get url
      rescue Mechanize::ResponseCodeError, SocketError, Timeout::Error, Errno::ECONNRESET,
              EOFError, Net::ProtocolError, OpenSSL::SSL::SSLError => e
        raise Relaton::RequestError, "Could not access #{url}: #{e.message}"
      end

      # Every edition of this recommendation, newest first.
      #
      # One request answers the whole family, and the response says so itself:
      # it lists every sibling `idrec`, and the payload for each of them is the
      # same one — verified byte-for-byte for 16818 and 14659 in
      # `spec/itu/vcr_cassettes/itu_t_h_264.yml`. So the result is published
      # under every sibling key, and the family's other 20 editions cost nothing.
      def editions
        @editions ||= begin
          rows = cache.fetch([:editions, idrec]) { fetch_editions }
          # Warmed after #fetch released the entry lock, so there is no
          # lock-order inversion between the table lock and an entry lock.
          cache.warm(siblings_of(rows), rows)
          rows
        end
      end

      def self_edition
        @self_edition ||= editions.find { |ed| ed["idrec"] == idrec }
      end

      def imp_status
        self_edition&.dig("status")
      end

      def imp_word_link
        return unless doc["imp_dms_link"]

        @doc_page ||= request_document(doc["imp_dms_link"])
        wrd_elm = @doc_page.at("//font[contains(.,'Word')]/../..")
        yield wrd_elm[:href] if block_given? && wrd_elm
      end

      def create_relation(type, title_text, id)
        titles = []
        if title_text && !title_text.empty?
          titles << Relaton::Bib::Title.new(content: title_text, language: "en", script: "Latn")
        end

        fref = titles.empty? ? id : nil
        did = Relaton::Bib::Docidentifier.new(type: "ITU", content: id, primary: true)
        bibitem = Relaton::Bib::ItemData.new(title: titles, formattedref: (fref ? Relaton::Bib::Formattedref.new(content: fref) : nil), docidentifier: [did])
        Relaton::Bib::Relation.new(type: type, bibitem: bibitem)
      end

      # Supplements to this recommendation.
      #
      # **Deliberately not shared across the family**, unlike #editions and
      # #fetch_workgroup. It very probably is family-invariant — supplements
      # belong to a recommendation, not to an edition — but that is an
      # assumption, and the only recording in the suite is a single
      # `getRecSupplements?idrec=14659`. Sharing it wrongly would give a
      # record another recommendation's `relation:` list, silently: the data
      # repo's `guard_enrichment` counts `contributor:` lines, which a wrongly
      # enriched record still has. What would settle it: add a
      # `getRecSupplements?idrec=16818` interaction to
      # `spec/itu/vcr_cassettes/itu_t_h_264.yml` and assert the two payloads
      # are equal; then key this on #family_id like the other two.
      def supplements
        @supplements ||= begin
          if imp
            []
          else
            url = RECSUPPLEMENTS % { idrec: idrec }
            get_data(url) || []
          end
        end
      end
    end
  end
end
