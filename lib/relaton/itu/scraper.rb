# frozen_string_literal: true

require "cgi"
require_relative "recommendation_parser"
require_relative "radio_regulations_parser"

module Relaton
  module Itu
    # Scraper.
    class Scraper
      attr_reader :hit, :imp

      TYPES = {
        "ISO" => "international-standard",
        "TS" => "technicalSpecification",
        "TR" => "technicalReport",
        "PAS" => "publiclyAvailableSpecification",
        "AWI" => "appruvedWorkItem",
        "CD" => "committeeDraft",
        "FDIS" => "finalDraftInternationalStandard",
        "NP" => "newProposal",
        "DIS" => "draftInternationalStandard",
        "WD" => "workingDraft",
        "R" => "recommendation",
        "Guide" => "guide",
      }.freeze

      def initialize(hit, imp: false)
        @hit = hit
        @imp = imp
      end

      def self.parse_page(hit, imp: false)
        new(hit, imp: imp).parse_page
      end

      # Parse page.
      # @return [Relaton::Itu::ItemData, nil]
      def parse_page # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        return unless parser.doc

        Relaton::Itu::ItemData.new(
          fetched: Date.today.to_s,
          type: "standard",
          docidentifier: docid,
          edition: edition,
          language: ["en"],
          script: ["Latn"],
          title: parser.fetch_titles,
          status: parser.fetch_status,
          date: parser.fetch_dates,
          abstract: parser.fetch_abstract,
          source: parser.fetch_source,
          relation: parser.fetch_relations,
          contributor: fetch_contributors,
          copyright: fetch_copyright,
          place: [Relaton::Bib::Place.new(city: "Geneva")],
          ext: Relaton::Itu::Ext.new(
            doctype: Relaton::Itu::Doctype.new(content: hit.hit[:type]),
            flavor: "itu",
          ),
        )
      end

      private

      def edition
        ed = parser.fetch_edition
        Relaton::Bib::Edition.new(content: ed) if ed
      end

      def idrec
        return @idrec if defined? @idrec

        @idrec = CGI.unescape(hit.hit[:url]).split("/").last.slice(/^\d+(?=-)/)&.to_i
      end

      def parser
        @parser ||= begin
          if idrec
            RecommendationParser.new hit.hit_collection.agent, idrec, imp
          else
            RadioRegulationsParser.new hit
          end
        end
      end

      # The primary docid comes from the hit's code; a recommendation additionally
      # carries the equivalent ISO/IEC(/IEEE) identifier, which used to be part of
      # the search result's media name and now comes from the recommendation
      # header's `iso_number` via the shared `RecommendationFields#iso_docid`.
      # Both are guarded on `idrec` — `RadioRegulationsParser` (RR/OB) parses an
      # HTML page and has neither `rec_name` nor `iso_docid`.
      #
      # @return [Array<Relaton::Bib::Docidentifier>]
      def docid
        @docid ||= begin
          docids = hit.hit[:code].to_s.split(" | ").map { |c| createdocid(c) }
          if idrec
            docids << createdocid("ITU-T #{parser.doc['rec_name']}") if docids.empty?
            iso = parser.iso_docid
            docids << iso if iso
          end
          docids
        end
      end

      # @param text [String]
      # @return [Relaton::Bib::Docidentifier]
      def createdocid(text) # rubocop:disable Metrics/MethodLength
        if text.match?(/^(?:ISO|ETSI)/)
          type = "ISO"
          text.match(/[^(]+/).to_s.strip.squeeze(" ")
        else
          type = "ITU"
          canonical_id text
        end => id
        Docidentifier.new(type: type, content: id, primary: true)
      end

      # The pubid spelling of an ITU code. The code is data from ITU, so a
      # form pubid cannot identify is kept as ITU wrote it.
      #
      # @param text [String]
      # @return [String]
      def canonical_id(text)
        ::Pubid::Itu.parse(text).to_s
      rescue ::Pubid::Errors::ParseError
        text
      end

      # @return [Array<Relaton::Bib::Contributor>]
      def fetch_contributors
        contribs = fetch_publisher_contributors
        eg = fetch_editorial_contributor
        contribs << eg if eg
        contribs
      end

      # @return [Array<Relaton::Bib::Contributor>]
      def fetch_publisher_contributors
        return [] unless hit.hit[:code]

        role = Relaton::Bib::Contributor::Role.new(type: "publisher")
        [Relaton::Bib::Contributor.new(organization: publisher_org,
                                       role: [role])]
      end

      # The publishing organization. Every ITU code names ITU, so a code pubid
      # cannot parse is still ITU's.
      #
      # @return [Relaton::Bib::Organization]
      def publisher_org
        Relaton::Bib::Organization.new(
          name: [Relaton::Bib::TypedLocalizedString.new(content: "International Telecommunication Union")],
          abbreviation: Relaton::Bib::LocalizedString.new(
            content: code_pubid&.publisher || "ITU",
          ),
          uri: [Relaton::Bib::Uri.new(content: "www.itu.int")],
        )
      end

      # The pubid parse of the hit's (first) code. nil when the hit has no
      # code, or when ITU spells it in a form pubid cannot identify.
      #
      # @return [Pubid::Itu::Identifiers::Base, nil]
      def code_pubid
        return @code_pubid if defined? @code_pubid

        code = hit.hit[:code].to_s.split(" | ").first
        @code_pubid = code && ::Pubid::Itu.parse(code)
      rescue ::Pubid::Errors::ParseError
        @code_pubid = nil
      end

      # The bureau letter (T, R or D) of the code: its sector, or the sector
      # of the document a wrapper (an annex, an appendix) belongs to. An
      # Operational Bulletin prints no sector (pubid#696), but TSB produces it.
      #
      # @return [String, nil]
      def bureau
        id = code_pubid
        return "T" if id.is_a? ::Pubid::Itu::Identifiers::SpecialPublication

        while id
          return id.sector.sector if id.sector

          id = wrapped(id)
        end
      end

      # The document a wrapper identifier belongs to, or nil.
      def wrapped(id)
        base = id.base if id.respond_to?(:base)
        base if base.is_a?(::Pubid::Identifier)
      end

      # @return [Relaton::Bib::Contributor, nil]
      def fetch_editorial_contributor
        wg_name = parser.fetch_workgroup
        return unless bureau

        org = Relaton::Bib::Organization.new(
          name: [Relaton::Bib::TypedLocalizedString.new(content: "International Telecommunication Union")],
          abbreviation: Relaton::Bib::LocalizedString.new(
            content: "ITU-#{bureau}",
          ),
          subdivision: group_subdivision(wg_name),
        )
        role = Relaton::Bib::Contributor::Role.new(
          type: "author",
          description: [Relaton::Bib::LocalizedMarkedUpString.new(content: "committee")],
        )
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

      # @return [Array<Relaton::Bib::Copyright>]
      def fetch_copyright
        owner = Relaton::Bib::ContributionInfo.new(organization: publisher_org)
        year = parser.doc_date&.match(/\d{4}/)&.to_s
        [Relaton::Bib::Copyright.new(from: year, owner: [owner])]
      end
    end
  end
end
