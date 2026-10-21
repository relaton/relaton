module Relaton
  module Iec
    # Parses Harmonized API project records (in-development standards) into
    # Relaton items. Field reference: the IEC/ISO Harmonized APIs technical
    # documentation, section "HAPI - Projects".
    class ProjectParser < DataParser
      # projectRelation types have no IEC-side reference, only a URN; map
      # them onto the bibdata relation vocabulary. Agreements carrying an
      # externalProject (Frankfurt agreement) have no URN and are skipped.
      RELATION_TYPES = {
        "AMENDS" => "updates",
        "CORRECTS" => "updates",
        "CORRECTED_BY" => "updatedBy",
        "REVISED_BY" => "updatedBy",
        "REPLACED_BY" => "obsoletedBy",
        "MERGED_INTO" => "mergedInto",
        "SPLIT_FROM" => "derivedFrom",
        "INTERPRETS" => "commentaryOf",
      }.freeze

      private

      # The project URN namespace differs from publications (iec:proj: vs
      # iec:std:), so the parent's URN-from-reference derivation does not
      # apply; the record's own urn is taken verbatim.
      def docidentifier
        ids = [iec_docid]
        ids << Docidentifier.new(content: @pub["urn"], type: "URN") if @pub["urn"]
        @errors[:docidentifier] &&= ids.compact.empty?
        ids.compact
      end

      def date
        result = {
          "published" => @pub["publicationDate"] || @pub["editionDate"],
          "created" => @pub["initialProjectDate"],
          "forecast" => @pub["forecastPublicationDate"],
        }.filter_map do |k, v|
          next unless v

          Bib::Date.new(type: k, at: v)
        end
        @errors[:date] &&= result.empty?
        result
      end

      # The stage lifecycle is the project's status: the CURRENT stage when
      # present, else the latest by effective date. stageCode is the IEC
      # abbreviation (CFDIS, WPUB, DELPUB...), harmonizedStageCode the
      # ISO-style numeric stage.
      def status
        stage = current_stage || Array(@pub["stages"]).last
        return unless stage

        result = Bib::Status.new(
          stage: Bib::Status::Stage.new(
            content: stage["harmonizedStageCode"], abbreviation: stage["stageCode"],
          ),
          iteration: stage["iteration"]&.to_s,
        )
        @errors[:status] &&= result.nil?
        result
      end

      def current_stage
        Array(@pub["stages"]).find { |s| s["status"] == "CURRENT" }
      end

      def contributor
        super + [owner_contributor].compact
      end

      def owner_contributor
        return unless @pub.dig("owner", "displayName")

        orgname = Bib::TypedLocalizedString.new(content: "International Electrotechnical Commission",
                                                language: "en", script: "Latn")
        abbr = Bib::LocalizedString.new(content: "IEC", language: "en", script: "Latn")
        tcname = Bib::TypedLocalizedString.new(content: @pub["owner"]["displayName"],
                                               language: "en", script: "Latn")
        subdivision = Bib::Subdivision.new(
          type: "technical-committee",
          name: [tcname],
        )
        org = Bib::Organization.new(name: [orgname], abbreviation: abbr, subdivision: [subdivision])
        desc = Bib::LocalizedMarkedUpString.new(content: "committee")
        role = Bib::Contributor::Role.new(type: "author", description: [desc])
        Bib::Contributor.new(organization: org, role: [role])
      end

      def relation
        rels = Array(@pub["projectRelations"]).filter_map { |r| project_relation r } +
               Array(@pub["publications"]).filter_map { |p| urn_relation "hasSuccessor", p["urn"] }
        @errors[:relation] &&= rels.empty?
        rels
      end

      def project_relation(rel)
        urn_relation RELATION_TYPES.fetch(rel["type"], "related"), rel["urn"]
      end

      def urn_relation(type, urn)
        return unless urn

        docid = Docidentifier.new(content: urn, type: "URN")
        bibitem = ItemData.new(formattedref: Bib::Formattedref.new(content: urn), docidentifier: [docid])
        Relation.new(type: type, bibitem: bibitem)
      end
    end
  end
end
