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
          edition: parser.fetch_edition,
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
            doctype: Relaton::Itu::Doctype.new(type: hit.hit[:type]),
            flavor: "itu",
          ),
        )
      end

      private

      def idrec
        return @idrec if defined? @idrec

        @idrec = CGI.unescape(hit.hit[:url]).split("/").last.slice(/^\d+(?=-)/)&.to_i
      end

      def parser
        @parser ||= begin
          if idrec
            RecommendationParser.new hit, idrec, imp
          else
            RadioRegulationsParser.new hit
          end
        end
      end

      # Fetch docid.
      # @return [Array<Relaton::Bib::Docidentifier>]
      def docid
        @docid ||= begin
          docids = hit.hit[:code].to_s.split(" | ").map { |c| createdocid(c) }
          docids << createdocid(doc["rec_name"]) if docids.empty?
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
          pubid = Pubid.parse(text)
          type = pubid.prefix
          pubid.to_s
        end => id
        Relaton::Bib::Docidentifier.new(type: type, content: id, primary: true)
      end

      # @return [Array<Relaton::Bib::Contributor>]
      def fetch_contributors
        return [] unless hit.hit[:code]

        abbrev = hit.hit[:code].sub(/-\w\s.*/, "")
        case abbrev
        when "ITU"
          name = "International Telecommunication Union"
          url = "www.itu.int"
        end
        org = Relaton::Bib::Organization.new(
          name: [Relaton::Bib::TypedLocalizedString.new(content: name)],
          abbreviation: Relaton::Bib::LocalizedString.new(content: abbrev),
          uri: [Relaton::Bib::Uri.new(content: url)],
        )
        role = Relaton::Bib::Contributor::Role.new(type: "publisher")
        [Relaton::Bib::Contributor.new(organization: org, role: [role])]
      end

      # @return [Array<Relaton::Bib::Copyright>]
      def fetch_copyright
        abbreviation = hit.hit[:code].match(/^[^-]+/).to_s
        case abbreviation
        when "ITU"
          name = "International Telecommunication Union"
          url = "www.itu.int"
        end
        org = Relaton::Bib::Organization.new(
          name: [Relaton::Bib::TypedLocalizedString.new(content: name)],
          abbreviation: Relaton::Bib::LocalizedString.new(content: abbreviation),
          uri: [Relaton::Bib::Uri.new(content: url)],
        )
        owner = Relaton::Bib::ContributionInfo.new(organization: org)
        [Relaton::Bib::Copyright.new(from: parser.doc_date, owner: [owner])]
      end
    end
  end
end
