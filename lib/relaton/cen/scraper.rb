# frozen_string_literal: true

module Relaton
  module Cen
    # Scraper.
    module Scraper
      COMMITTEES = {
        "TC 459" =>
          "ECISS - European Committee for Iron and Steel Standardization",
      }.freeze

      class << self
        # Parse page.
        # @param hit [RelatonCen::Hit]
        # @return [RelatonIsoBib::IsoBibliographicItem]
        def parse_page(hit) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          doc = hit.hit_collection.agent.get hit.hit[:url]
          ItemData.new(
            fetched: Date.today.to_s,
            type: "standard",
            docidentifier: fetch_docid(hit.hit[:code]),
            language: ["en"],
            script: ["Latn"],
            title: fetch_titles(doc),
            status: fetch_status(doc),
            date: fetch_dates(doc),
            contributor: fetch_contributors(doc),
            # editorialgroup: fetch_editorialgroup(doc),
            abstract: fetch_abstract(doc),
            copyright: fetch_copyright(doc),
            source: fetch_source(doc.uri.to_s),
            relation: fetch_relations(doc),
            place: [Bib::Place.new(city: "London")],
            ext: fetch_ext(doc, hit)
          )
        end

        private

        # @param doc [Mechanize::Page]
        # @return [Array<Relaton::Bib::ICS>]
        def fetch_ics(doc)
          doc.xpath("//tr[th[.='ICS']]/td/text()").filter_map do |ics|
            ics_code = ics.text.match(/[^\s]+/).to_s.gsub("\u00A0", "")
            next if ics_code.empty?

            isoics = Isoics.fetch(ics_code)
            Bib::ICS.new code: ics_code, text: isoics.description
          end
        end

        # Fetch abstracts.
        # @param doc [Mechanize::Page]
        # @return [Array<Relaton::Bib::LocalizedMarkedUpString>]
        def fetch_abstract(doc)
          content = doc.at("//tr[th[.='Abstract/Scope']]/td")
          [Bib::Abstract.new(content: content.text, language: "en", script: "Latn")]
        end

        # Fetch docid.
        # @param ref [String]
        # @return [Array<Relaton::Cen::Docidentifier>]
        def fetch_docid(ref)
          [Docidentifier.new(type: "CEN", content: ref, primary: true)]
        end

        # Fetch status.
        # @param doc [Mechanize::Page]
        # @return [Relaton::Bib::DocumentStatus, nil]
        def fetch_status(doc)
          s = doc.at("//tr[th[.='Status']]/td")
          return unless s

          stage = Bib::Status::Stage.new(content: s.text.strip)
          Bib::Status.new(stage: stage)
        end

        # @param hit [RelatonCen::Hit]
        # @return [Relaton::Bib::StructuredIdentifier]
        def fetch_structuredid(hit)
          %r{(?<docnum>\d+)(?:-(?<part>\d+))?(?:-(?<subpart>\d+))?} =~ hit[:code]
          partnumber = [part, subpart].compact.join(":")
          StructuredIdentifier.new(docnumber: docnum, partnumber: partnumber, agency: ["CEN"])
        end

        # Fetch relations.
        # @param doc [Mechanize::Page]
        # @return [Array<Relaton::Bib::Relation>]
        def fetch_relations(doc)
          doc.xpath(
            "//div[@id='DASHBOARD_LISTRELATIONS']/table/tr[th[.!='Sales Points']]",
          ).each_with_object([]) do |rt, acc|
            type = relation_type rt.at("th").text.downcase
            rt.xpath("td/a").each do |r|
              acc << Bib::Relation.new(type: type, bibitem: create_relation(r))
            end
          end
        end

        def relation_type(type)
          case type
          when "supersedes" then "obsoletes"
          when "superseded by" then "obsoletedBy"
          when /bibliographic references/ then "cites"
          when /normative reference/ then "cites"
          else type
          end
        end

        def create_relation(rel)
          source = fetch_source HitCollection::DOMAIN + rel[:href]
          ItemData.new(formattedref: Bib::Formattedref.new(content: rel.text), type: "standard", source: source)
        end

        # Fetch titles.
        # @param doc [Mechanize::Page]
        # @return [Array<Relaton::Bib::Title>]
        def fetch_titles(doc)
          te = doc.at("//tr[th[.='Title']]/td").text.strip
          Bib::Title.from_string te, "en", "Latn"
        end

        # Fetch dates
        # @param hit [Mechanize::Page]
        # @return [Array<Relaton::Bib::Date>]
        def fetch_dates(doc) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/MethodLength
          doc.xpath("//div[@id='DASHBOARD_LISTIMPLEMENTATIONDATES']/table/tr")
            .each_with_object([]) do |d, acc|
            at = d.at("td").text
            next if at.empty?

            t = d.at("th").text
            type = case t
                  when /DOR/ then "adapted"
                  when /DAV/ then "issued"
                  when /DOA/ then "announced"
                  when /DOP/ then "published"
                  when /DOW/ then "obsoleted"
                  else t.downcase
                  end
            acc << Bib::Date.new(type: type, at: at)
          end
        end

        # Fetch contributors
        # @param doc [Mechanize::Page]
        # @return [Array<Relaton::Bib::Contributor>]
        def fetch_contributors(doc)
          code = doc.at("//tr/td/h1/text()").text
          title = doc.at("//tr/td[3]/h1").text
          %r{/(?<type>\w+)(?:\s(?<num>[^/]+))?$} =~ code
          org = owner_entity

          COMMITTEES.each do |k, name|
            next unless code.include? k

            wg_type, number = k.split
            org.subdivision << create_subdivision("technical-committee", name, wg_type, number)
          end

          subdiv_type = org.subdivision.any? ? "subcommittee" : "technical-committee"
          org.subdivision << create_subdivision(subdiv_type, title, type, num)
          role_desc = Bib::LocalizedMarkedUpString.new(content: "committee")
          role = Bib::Contributor::Role.new(type: "author", description: [role_desc])
          [Bib::Contributor.new(role: [role], organization: org)]
        end

        def create_subdivision(type, name, subtype, wg_num = nil)
          subdiv_name = Bib::TypedLocalizedString.new(content: name)
          id = Array(wg_num).map { |wn| Bib::OrganizationType::Identifier.new(type: "number", content: wg_num) }
          Bib::Subdivision.new( type: type, subtype: subtype, name: [subdiv_name], identifier: id)
        end

        # Fetch links.
        # @param url [String]
        # @return [Array<Relaton::Bib::Uri>]
        def fetch_source(url)
          [Bib::Uri.new(type: "src", content: url)]
        end

        # Fetch copyright.
        # @param doc [Mechanize::Page]
        # @return [Array<Bib::Copyright>]
        def fetch_copyright(doc)
          date = doc.at("//tr[th[.='date of Availability (DAV)']]/td").text
          owner = Bib::ContributionInfo.new(organization: owner_entity)
          from = date.match(/^\d{4}/).to_s
          [Bib::Copyright.new(owner: [owner], from: from)]
        end

        # @return [Hash]
        def owner_entity
          org_name = Bib::TypedLocalizedString.new(content: "European Committee for Standardization")
          org_abbr = Bib::TypedLocalizedString.new(content: "CEN")
          uri = Bib::Uri.new(content: "https://cen.eu")
          Bib::Organization.new(name: [org_name], abbreviation: org_abbr, uri: [uri])
        end

        def fetch_ext(doc, hit)
          Ext.new(
            doctype: Bib::Doctype.new(content: "international-standard"),
            flavor: "cen",
            ics: fetch_ics(doc),
            structuredidentifier: fetch_structuredid(hit.hit),
          )
        end
      end
    end
  end
end
