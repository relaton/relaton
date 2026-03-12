require_relative "pubid"
module Relaton
  module Etsi
    class DataParser
      ATTRS = %i[
        title docnumber source date docidentifier version status contributor
        keyword ext abstract language script
      ].freeze

      def initialize(row)
        @row = row
      end

      def parse
        args = ATTRS.each_with_object({}) do |attr, hash|
          hash[attr] = send(attr)
        end
        ItemData.new(**args)
      end

      def pubid
        @pubid ||= PubId.parse(@row["ETSI deliverable"])
      end

      def title
        [Bib::Title.new(content: @row["title"], language: "en", script: "Latn")]
      end

      def docnumber
        @row["ETSI deliverable"]
      end

      def source
        urls = []
        urls << Bib::Uri.new(content: @row["Details link"], type: "src")
        urls << Bib::Uri.new(content: @row["PDF link"], type: "pdf")
      end

      def date
        return [] unless pubid.date

        [Bib::Date.new(type: "published", at: pubid.date)]
      end

      def docidentifier
        [Bib::Docidentifier.new(content: @row["ETSI deliverable"], type: "ETSI", primary: true)]
      end

      def version
        return [] unless pubid.version

        [Bib::Version.new(draft: pubid.version)]
      end

      def status
        stage = @row["Status"] == "On Approval" ? "#{pubid.type} approval" : @row["Status"]
        Status.new(stage: stage)
      end

      def contributor
        contribs = [publisher_contributor]
        contribs << committee_contributor if @row["Technical body"]
        contribs
      end

      def publisher_contributor
        org = Bib::Organization.new(
          name: [etsi_org_name], abbreviation: etsi_abbreviation,
        )
        role = Bib::Contributor::Role.new(type: "publisher")
        Bib::Contributor.new(organization: org, role: [role])
      end

      def etsi_org_name
        Bib::TypedLocalizedString.new(
          content: "European Telecommunications Standards Institute",
          language: "en",
          script: "Latn",
        )
      end

      def etsi_abbreviation
        Bib::LocalizedString.new(
          content: "ETSI",
          language: "en",
          script: "Latn",
        )
      end

      def committee_contributor
        desc = Bib::LocalizedMarkedUpString.new(content: "committee")
        role = Bib::Contributor::Role.new(
          type: "author", description: [desc],
        )
        Bib::Contributor.new(organization: committee_org, role: [role])
      end

      def committee_org
        Bib::Organization.new(
          name: [etsi_name],
          abbreviation: etsi_abbreviation,
          subdivision: [technical_committee_subdivision],
        )
      end

      def etsi_name
        Bib::TypedLocalizedString.new(
          content: "European Telecommunications Standards Institute",
        )
      end

      def technical_committee_subdivision
        Bib::Subdivision.new(
          name: [Bib::TypedLocalizedString.new(
            content: @row["Technical body"],
          )],
          type: "technical-committee",
        )
      end

      def keyword
        taxon = @row["Keywords"].split(",").map do |kw|
          Bib::LocalizedString.new(content: kw.strip, language: "en", script: "Latn")
        end
        return [] if taxon.empty?

        [Bib::Keyword.new(taxon: taxon)]
      end

      def ext
        Ext.new(doctype: doctype)
      end

      def doctype
        Doctype.create_from_abbreviation pubid.type
      end

      def abstract
        return [] unless @row["Scope"]

        [Bib::LocalizedMarkedUpString.new(content: @row["Scope"], language: "en", script: "Latn")]
      end

      def language
        ["en"]
      end

      def script
        ["Latn"]
      end
    end
  end
end
