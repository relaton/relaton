require_relative "../itu"
require_relative "recommendation_parser"

module Relaton
  module Itu
    # Parse a single row of the ITU-T recommendation index returned by the
    # mws/api/recommendations/searchRecs endpoint (see DataFetcher#search_recs)
    # into an ItemData. Recommendations and supplements share one row schema and
    # are distinguished by "Suppl" in rec_name; each edition is its own row, so
    # the docid keeps the (MM/YYYY) edition date (e.g. "ITU-T A.1 (10/2000)") —
    # which Pubid::Itu parses per edition, keeping index rows and filenames
    # unique across editions. Mirrors DataParserR (the ITU-R search parser).
    #
    # The searchRecs row is metadata-thin (docid/title/date/source/doctype). When
    # an `agent` is given, each record is **enriched** with the same
    # `getRecHdrDetail`-sourced fields the live runtime path emits — abstract,
    # ISO/IEC co-identifier, editorial-group contributors, status — via the shared
    # `RecommendationFields` (through `RecommendationParser`), so the harvested
    # record matches a live `Bibliography.get`. Enrichment is best-effort: a
    # detail-fetch failure degrades to the thin record rather than losing it.
    module DataParserT
      extend self

      # rec_name markers → Doctype. Ordered; first match wins. A plain edition
      # (no marker) is a "recommendation". Values are members of Doctype::TYPES.
      DOCTYPE_MARKERS = {
        /\bSuppl\b/ => "recommendation-supplement",
        /\bAmd\b/ => "recommendation-amendment",
        /\bCor\b/ => "recommendation-corrigendum",
        /\bAnnex\b/ => "recommendation-annex",
      }.freeze

      # The `errors` hash is threaded through the fetch_* helpers rather than
      # held in an ivar: this module is `extend self`, so an ivar would be state
      # shared by every caller — and DataFetcher#fetch_recommendations parses
      # rows from a pool of threads.
      #
      # @param row [Hash] single row from searchRecs Data
      # @param agent [Mechanize, nil] when present, enrich via getRecHdrDetail
      # @param errors [Hash]
      # @return [Relaton::Itu::ItemData, nil]
      def parse(row, agent = nil, errors = {})
        docid = fetch_docid(row, errors)
        return if docid.empty?

        enr = enrichment(row, agent)
        date = fetch_date(row, errors)
        Relaton::Itu::ItemData.new(
          docidentifier: docid + enr.fetch(:iso, []),
          title: fetch_title(row, errors),
          edition: enr[:edition],
          abstract: enr.fetch(:abstract, []),
          date: date, language: ["en"],
          status: enr[:status],
          relation: enr.fetch(:relation, []),
          contributor: enr.fetch(:contributor, []),
          copyright: fetch_copyright(date),
          place: [Relaton::Bib::Place.new(city: "Geneva")],
          source: fetch_source(row, errors), script: ["Latn"],
          type: "standard",
          ext: Relaton::Itu::Ext.new(doctype: fetch_doctype(row, errors), flavor: "itu"),
        )
      end

      # Best-effort getRecHdrDetail enrichment for one record. Returns {} when
      # there is no agent or the detail fetch fails, so the record still gets its
      # thin fields. ITU-T records are always sector T → abbreviation "ITU",
      # bureau "T".
      #
      # @param row [Hash]
      # @param agent [Mechanize, nil]
      # @return [Hash] { iso:, abstract:, status:, contributor: }
      def enrichment(row, agent)
        return {} unless agent && row["idrec"]

        f = RecommendationParser.new(agent, row["idrec"], false)
        ed = f.fetch_edition
        {
          iso: Array(f.iso_docid),
          abstract: f.fetch_abstract,
          status: f.fetch_status,
          edition: (Relaton::Bib::Edition.new(content: ed) if ed),
          relation: f.fetch_relations,
          contributor: [f.publisher("ITU"), f.editorial_group("T")].compact,
        }
      rescue StandardError => e
        Util.warn "ITU-T enrichment failed for idrec=#{row['idrec']}: #{e.message}"
        {}
      end

      # The ITU copyright, from the record's own publication year — no detail
      # fetch needed, so a thin (un-enriched) record carries it too. Mirrors
      # `Scraper#fetch_copyright` on the live path.
      #
      # @param date [Array<Relaton::Bib::Date>] the record's dates
      # @return [Array<Relaton::Bib::Copyright>]
      def fetch_copyright(date)
        year = date.first&.at.to_s[/\d{4}/]
        return [] unless year

        org = Relaton::Bib::Organization.new(
          name: [Relaton::Bib::TypedLocalizedString.new(content: "International Telecommunication Union")],
          abbreviation: Relaton::Bib::LocalizedString.new(content: "ITU"),
          uri: [Relaton::Bib::Uri.new(content: "www.itu.int")],
        )
        owner = [Relaton::Bib::ContributionInfo.new(organization: org)]
        [Relaton::Bib::Copyright.new(from: year, owner: owner)]
      end

      # The primary docid is the rec_name prefixed with "ITU-T", keeping the
      # trailing " (MM/YYYY)" edition date so Pubid::Itu identifies each edition
      # distinctly (matches the existing "ITU-T L.163 (11/2018)" convention).
      #
      # @param row [Hash]
      # @return [Array<Relaton::Itu::Docidentifier>]
      def fetch_docid(row, errors = {})
        name = row["rec_name"].to_s.strip
        if name.empty?
          errors[:docid] &&= true
          return []
        end

        r = [Docidentifier.new(type: "ITU", content: "ITU-T #{name}", primary: true)]
        errors[:docid] &&= r.empty?
        r
      end

      # @param row [Hash]
      # @return [Array<Relaton::Bib::Title>]
      def fetch_title(row, errors = {})
        content = row["title"].to_s.strip
        r = content.empty? ? [] : [Relaton::Bib::Title.new(type: "main", content: content, language: "en", script: "Latn")]
        errors[:title] &&= r.empty?
        r
      end

      # Prefer a full day-precision approval_date (YYYY-MM-DD, matching the live
      # runtime path); fall back to the (MM/YYYY) edition date in rec_name; and
      # only then to a coarser (year / year-month) approval_date. Ordering this way
      # means a coarse or malformed approval_date never downgrades precision below
      # the always-well-formed rec_name edition date.
      #
      # @param row [Hash]
      # @return [Array<Relaton::Bib::Date>]
      def fetch_date(row, errors = {})
        approval = row["approval_date"].to_s
        date = approval[/\d{4}-\d{2}-\d{2}/] || rec_name_date(row["rec_name"]) || approval[/\d{4}(-\d{2})?/]
        if date.nil? || date.empty?
          errors[:date] &&= true
          return []
        end

        r = [Relaton::Bib::Date.new(type: "published", at: date)]
        errors[:date] &&= r.empty?
        r
      end

      # @param row [Hash]
      # @return [Array<Relaton::Bib::Uri>]
      def fetch_source(row, errors = {})
        link = row["dms_link"].to_s.strip
        if link.empty? || link == "-"
          errors[:source] &&= true
          return []
        end

        r = [Relaton::Bib::Uri.new(type: "src", content: link)]
        errors[:source] &&= r.empty?
        r
      end

      # @param row [Hash]
      # @return [Relaton::Itu::Doctype]
      def fetch_doctype(row, errors = {})
        name = row["rec_name"].to_s
        content = DOCTYPE_MARKERS.find { |re, _| name.match?(re) }&.last || "recommendation"
        errors[:doctype] &&= false
        Doctype.new(content: content)
      end

      private

      # "A.1 (10/2000)" -> "2000-10"
      # @param name [String, nil]
      # @return [String, nil]
      def rec_name_date(name)
        return unless name =~ %r{\((\d{2})/(\d{4})\)}

        "#{$2}-#{$1}"
      end
    end
  end
end
