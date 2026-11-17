module Relaton
  module Doi
    #
    # Map a DataCite record (the `data.attributes` of
    # `GET api.datacite.org/dois/<doi>`, DataCite Metadata Schema 4) to a
    # generic Bib::ItemData.
    #
    class DataciteParser # rubocop:disable Metrics/ClassLength
      # DataCite `types.resourceTypeGeneral` → Relaton item type.
      RESOURCE_TYPES = {
        "Audiovisual" => "audiovisual",
        "Book" => "book",
        "BookChapter" => "inbook",
        "ConferencePaper" => "inproceedings",
        "ConferenceProceeding" => "proceedings",
        "Dataset" => "dataset",
        "Dissertation" => "thesis",
        "Image" => "graphic_work",
        "Journal" => "journal",
        "JournalArticle" => "article",
        "Report" => "techreport",
        "Software" => "software",
        "Standard" => "standard",
      }.freeze

      # DataCite `types.bibtex` → Relaton item type, for the general types
      # the table above leaves open (`Text`, `Other`, …).
      BIBTEX_TYPES = {
        "article" => "article",
        "book" => "book",
        "inbook" => "inbook",
        "incollection" => "incollection",
        "inproceedings" => "inproceedings",
        "manual" => "manual",
        "mastersthesis" => "thesis",
        "phdthesis" => "thesis",
        "proceedings" => "proceedings",
        "techreport" => "techreport",
        "unpublished" => "unpublished",
      }.freeze

      # DataCite `dateType` → Relaton date type. The other DataCite types
      # (Accepted, Available, Collected, Copyrighted, Submitted, Valid, …)
      # have no Relaton counterpart.
      DATE_TYPES = {
        "Issued" => "issued",
        "Created" => "created",
        "Updated" => "updated",
      }.freeze

      # DataCite `relationType` → Relaton relation type. Any other type is
      # `related`, with the DataCite type as the description.
      RELATION_TYPES = {
        "IsCitedBy" => "isCitedIn",
        "Cites" => "cites",
        "IsReferencedBy" => "isCitedIn",
        "References" => "cites",
        "IsSupplementTo" => "complementOf",
        "IsSupplementedBy" => "hasComplement",
        "IsContinuedBy" => "hasSuccessor",
        "Continues" => "successorOf",
        "IsDescribedBy" => "describedBy",
        "Describes" => "describes",
        "IsDocumentedBy" => "describedBy",
        "Documents" => "describes",
        "HasVersion" => "hasEdition",
        "IsVersionOf" => "editionOf",
        "IsNewVersionOf" => "updates",
        "IsPreviousVersionOf" => "updatedBy",
        "IsPartOf" => "partOf",
        "HasPart" => "hasPart",
        "IsPublishedIn" => "includedIn",
        "IsDerivedFrom" => "derivedFrom",
        "IsSourceOf" => "derives",
        "IsReviewedBy" => "hasReview",
        "Reviews" => "reviewOf",
        "IsObsoletedBy" => "obsoletedBy",
        "Obsoletes" => "obsoletes",
        "IsRequiredBy" => "complementOf",
        "Requires" => "hasComplement",
        "IsTranslationOf" => "translatedFrom",
        "HasTranslation" => "hasTranslation",
        "IsVariantFormOf" => "manifestationOf",
        "IsOriginalFormOf" => "hasManifestation",
      }.freeze

      # DataCite's standard values for an unknown property (`(:unav)`
      # unavailable, `(:unkn)` unknown, …). They are not names.
      PLACEHOLDER = /\A\(:[a-z]+\)\z/

      ATTRS = %i[type fetched title docidentifier date source abstract
                 contributor language relation].freeze

      #
      # @param [Hash] src the record's `attributes`
      #
      # @return [Bib::ItemData]
      #
      def self.parse(src)
        new(src).parse
      end

      def initialize(src)
        @src = src
      end

      def parse
        Bib::ItemData.new(**ATTRS.to_h { |a| [a, send("parse_#{a}")] })
      end

      private

      def parse_type
        types = @src["types"] || {}
        RESOURCE_TYPES[types["resourceTypeGeneral"]] ||
          BIBTEX_TYPES[types["bibtex"]] || "misc"
      end

      def parse_fetched
        Date.today.to_s
      end

      def parse_title
        Array(@src["titles"]).filter_map do |t|
          next if t["title"].to_s.strip.empty?

          type = t["titleType"] == "Subtitle" ? "subtitle" : "main"
          Bib::Title.new(type: type, content: t["title"].strip, language: t["lang"])
        end
      end

      def parse_docidentifier
        [Bib::Docidentifier.new(type: "DOI", content: @src["doi"], primary: true)]
      end

      def parse_date
        dates = Array(@src["dates"]).filter_map do |d|
          type = DATE_TYPES[d["dateType"]]
          create_date(type, d["date"].to_s.strip) if type
        end
        if dates.none? { |d| d.type == "issued" } && @src["publicationYear"]
          dates.unshift Bib::Date.new(type: "issued", at: @src["publicationYear"].to_s)
        end
        dates
      end

      #
      # A DataCite date is free text: a date, an RKMS-ISO8601 range
      # (`2019-01-01/2020-02-02`, either end may be open), or prose
      # (`Spring 2019`). A date Relaton cannot read is skipped, never raised.
      #
      def create_date(type, value)
        return if value.empty?

        if value.include?("/")
          from, to = value.split("/", 2).map { |v| v.strip.empty? ? nil : v.strip }
          Bib::Date.new(type: type, from: from, to: to) if from || to
        else
          Bib::Date.new(type: type, at: value)
        end
      rescue ::Date::Error, ArgumentError
        nil
      end

      def parse_source
        return [] unless @src["url"]

        [Bib::Uri.new(type: "src", content: @src["url"])]
      end

      def parse_abstract
        Array(@src["descriptions"]).filter_map do |d|
          next unless d["descriptionType"] == "Abstract" && d["description"]

          Bib::Abstract.new(content: d["description"], language: d["lang"])
        end
      end

      def parse_language
        Array(@src["language"])
      end

      def parse_contributor
        contribs = Array(@src["creators"]).filter_map { |c| contributor(entity(c), "author") }
        contribs += Array(@src["contributors"]).filter_map { |c| typed_contributor c }
        contribs << contributor(create_org(publisher_name), "publisher") if publisher_name
        contribs
      end

      def publisher_name
        pub = @src["publisher"]
        name = pub.is_a?(Hash) ? pub["name"] : pub
        name unless name.nil? || name.match?(PLACEHOLDER)
      end

      # DataCite `contributorType` → Relaton role. The other types
      # (ContactPerson, DataCollector, HostingInstitution, ProjectMember, …)
      # have no Relaton role; an author role would make a citation name them
      # as authors, so they are left out.
      CONTRIBUTOR_ROLES = {
        "Editor" => "editor",
        "Distributor" => "distributor",
        "Sponsor" => "enabler",
        "RightsHolder" => "owner",
      }.freeze

      def typed_contributor(contrib)
        role = CONTRIBUTOR_ROLES[contrib["contributorType"]]
        contributor(entity(contrib), role) if role
      end

      def contributor(entity, type)
        return unless entity

        role = [Bib::Contributor::Role.new(type: type)]
        if entity.is_a?(Bib::Person)
          Bib::Contributor.new(role: role, person: entity)
        else
          Bib::Contributor.new(role: role, organization: entity)
        end
      end

      #
      # DataCite marks a name `Personal` or `Organizational`, but the type is
      # optional. An untyped name is a person when it has name parts or reads
      # `Family, Given`.
      #
      def entity(name)
        if organization?(name)
          create_org(name["name"]) unless name["name"].to_s.strip.empty?
        elsif person_name_parts(name).first
          create_person(name)
        end
      end

      def organization?(name)
        return true if name["nameType"] == "Organizational"
        return false if name["nameType"] == "Personal"

        !name["familyName"] && !name["name"].to_s.include?(",")
      end

      def create_person(name)
        Bib::Person.new(
          name: create_person_name(name),
          affiliation: Array(name["affiliation"]).filter_map { |a| affiliation a },
          identifier: orcid(name),
        )
      end

      #
      # @return [Array<String, nil>] the family and given names
      #
      def person_name_parts(name)
        family = name["familyName"].to_s.strip
        return [family, name["givenName"]&.strip] unless family.empty?

        family, given = name["name"].to_s.split(",", 2).map(&:strip)
        [family.to_s.empty? ? nil : family, given]
      end

      def create_person_name(name)
        family, given = person_name_parts(name)
        given = nil if given.to_s.empty?
        Bib::FullName.new(
          surname: Bib::LocalizedString.new(content: family),
          forename: given ? [Bib::FullNameType::Forename.new(content: given)] : [],
        )
      end

      def affiliation(aff)
        org = aff.is_a?(Hash) ? aff["name"] : aff
        Bib::Affiliation.new(organization: create_org(org)) if org
      end

      def orcid(name)
        Array(name["nameIdentifiers"]).filter_map do |id|
          next unless id["nameIdentifierScheme"]&.casecmp?("ORCID") && id["nameIdentifier"]

          Bib::Person::Identifier.new(type: "orcid", content: id["nameIdentifier"])
        end
      end

      def create_org(name)
        Bib::Organization.new(name: [Bib::TypedLocalizedString.new(content: name)])
      end

      def parse_relation
        Array(@src["relatedIdentifiers"]).filter_map do |rel|
          next unless rel["relatedIdentifierType"] == "DOI" && rel["relatedIdentifier"]

          docid = Bib::Docidentifier.new(type: "DOI", content: rel["relatedIdentifier"])
          bibitem = Bib::ItemBase.new(docidentifier: [docid])
          type = RELATION_TYPES[rel["relationType"]]
          desc = Bib::LocalizedMarkedUpString.new(content: rel["relationType"]) unless type
          Bib::Relation.new(type: type || "related", description: desc, bibitem: bibitem)
        end
      end
    end
  end
end
