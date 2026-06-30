# frozen_string_literal: true

module Relaton
  module Ogc
    class Scraper
      TYPES = {
        "AS" => { type: "abstract-specification-topic" },
        "BP" => { type: "best-practice", subtype: "general" },
        "CAN" => { type: "standard", subtype: "general", stage: "draft" },
        "CR" => { type: "change-request-supporting-document" },
        "CP" => { type: "community-practice" },
        "CS" => { type: "community-standard" },
        "DP" => { type: "discussion-paper" },
        "DP-Draft" => { type: "discussion-paper", stage: "draft" },
        "IPR" => { type: "engineering-report" },
        "IS" => { type: "standard", subtype: "implementation" },
        "ISC" => { type: "standard", subtype: "implementation" },
        "ISx" => { type: "standard", subtype: "extension" },
        "Notes" => { type: "other" },
        "ORM" => { type: "reference-model" },
        "PC" => { type: "standard", subtype: "profile" },
        "PER" => { type: "engineering-report" },
        "POL" => { type: "standard" },
        "Primer" => { type: "other" },
        "Profile" => { type: "standard", subtype: "profile" },
        "RFC" => { type: "standard", stage: "draft" },
        "SAP" => { type: "standard", subtype: "profile" },
        "WhitePaper" => { type: "white-paper" },
        "ATB" => { type: "other" },
        "RP" => { type: "discussion-paper" },
      }.freeze

      def self.parse_page(hit, errors = Hash.new(true))
        new(hit, errors).parse
      end

      # @param hit [Hash]
      # @param errors [Hash]
      def initialize(hit, errors = Hash.new(true))
        @hit = hit
        @errors = errors
      end

      # @return [Relaton::Ogc::ItemData]
      def parse # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
        type = fetch_type(@hit["type"])
        contribs = fetch_contributor(@hit)
        contribs << fetch_editorialgroup_contributor
        ItemData.new(
          type: "standard",
          title: fetch_title(@hit["title"]),
          docidentifier: fetch_docid(@hit["identifier"]),
          source: fetch_link(@hit),
          status: fetch_status(type[:stage]),
          edition: fetch_edition(@hit["identifier"]),
          abstract: fetch_abstract(@hit["description"]),
          contributor: contribs,
          language: ["en"],
          script: ["Latn"],
          date: fetch_date(@hit["date"]),
          ext: Ext.new(
            doctype: fetch_doctype(type[:type]),
            subdoctype: type[:subtype],
            flavor: "ogc",
          ),
        )
      end

      private

      def fetch_editorialgroup_contributor # rubocop:disable Metrics/MethodLength
        desc = Bib::LocalizedMarkedUpString.new(content: "committee")
        role = Bib::Contributor::Role.new(
          type: "author", description: [desc],
        )
        ogc = "Open Geospatial Consortium"
        org = Bib::Organization.new(
          name: [Bib::TypedLocalizedString.new(content: ogc)],
          abbreviation: Bib::LocalizedString.new(content: "OGC"),
          subdivision: [Bib::Subdivision.new(
            type: "technical-committee",
            name: [Bib::TypedLocalizedString.new(content: "technical")],
          )],
        )
        Bib::Contributor.new(role: [role], organization: org)
      end

      # @param title [String]
      # @return [Array<Bib::Title>]
      def fetch_title(title)
        result = Bib::Title.from_string title, "en", "Latn"
        @errors[:title] &&= result.empty?
        result
      end

      # @param identifier [String]
      # @return [Array<Bib::Docidentifier>]
      def fetch_docid(identifier)
        @errors[:docid] &&= identifier.to_s.strip.empty?
        id = Docidentifier.new(
          content: identifier, type: "OGC", primary: true,
        )
        [id]
      end

      # @param hit [Hash]
      # @return [Array<Bib::Uri>]
      def fetch_link(hit) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity,Metrics/MethodLength
        link = []
        uri = hit["URI"].to_s.strip
        unless uri.empty?
          link << Bib::Uri.new(type: "src", content: uri)
        end
        return link unless hit["URL"] && !hit["URL"].strip.empty?

        type = link_type(hit["URL"])
        link << Bib::Uri.new(type: type, content: hit["URL"].strip)
      ensure
        @errors[:link] &&= link.empty?
      end

      def link_type(url)
        ext = url.match(/(?<=\.)(?<ext>pdf|html|doc)$/)
        return ext[:ext] if ext

        case url
        when /portal\.(ogc|opengeospatial)\.org/,
             /usgif\.org/
          "pdf"
        else "html"
        end
      end

      # @param type [String]
      # @return [Doctype]
      def fetch_doctype(type)
        Doctype.new(content: type)
      end

      # @param type [String]
      # @return [Hash]
      def fetch_type(type)
        TYPES[type.sub(/^D-/, "")] || { type: "other" }
      end

      # @param stage [String, nil]
      # @return [Bib::Status, nil]
      def fetch_status(stage)
        @errors[:status] &&= stage.nil?
        return unless stage

        stg = Bib::Status::Stage.new(content: stage)
        Bib::Status.new(stage: stg)
      end

      # @param identifier [String]
      # @return [String, nil]
      def fetch_edition(identifier)
        %r{(?<=r)(?<edition>\d+)$} =~ identifier
        @errors[:edition] &&= edition.nil?
        edition && Bib::Edition.new(content: edition)
      end

      # @param description [String]
      # @return [Array<Bib::LocalizedMarkedUpString>]
      def fetch_abstract(description)
        @errors[:abstract] &&= description.to_s.strip.empty?
        abs = Bib::Abstract.new(
          content: description, language: "en", script: "Latn",
        )
        [abs]
      end

      # @param doc [Hash]
      # @return [Array<Bib::Contributor>]
      def fetch_contributor(doc)
        contribs = doc["creator"].to_s.split(", ").map do |name|
          person_contrib name
        end
        contribs << org_contrib(doc["publisher"]) if doc["publisher"]
        @errors[:contributor] &&= contribs.empty?
        contribs
      end

      # @param name [String]
      # @return [Bib::Contributor]
      def person_contrib(name)
        Bib::Contributor.new(
          person: Bib::Person.new(
            name: Bib::FullName.new(
              completename: Bib::LocalizedString.new(content: name),
            ),
          ),
          role: [Bib::Contributor::Role.new(type: "author")],
        )
      end

      # @param name [String]
      # @return [Bib::Contributor]
      def org_contrib(name)
        Bib::Contributor.new(
          organization: Bib::Organization.new(
            name: [Bib::TypedLocalizedString.new(content: name)],
          ),
          role: [Bib::Contributor::Role.new(type: "publisher")],
        )
      end

      # @param date [String, nil]
      # @return [Array<Bib::Date>]
      def fetch_date(date)
        result = if date
                   [Bib::Date.new(type: "published", at: date)]
                 else
                   []
                 end
        @errors[:date] &&= result.empty?
        result
      rescue Date::Error
        @errors[:date] &&= true
        []
      end
    end
  end
end
