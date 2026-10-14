# frozen_string_literal: true

module Relaton
  module Evs
    # Scraper.
    module Scraper
      class << self
        # Parse page.
        # @param hit [Relaton::Evs::Hit]
        # @return [Relaton::Evs::ItemData]
        def parse_page(hit)
          doc = hit.hit_collection.agent.get hit.hit[:url]
          id = hit.pubid
          lang = id&.language == "et" ? "et" : "en"
          date = fetch_date(doc)

          ItemData.new(
            fetched: Date.today.to_s,
            type: "standard",
            docidentifier: fetch_docid(doc),
            language: [lang],
            script: ["Latn"],
            title: fetch_titles(doc, lang),
            date: date ? [date] : [],
            contributor: fetch_contributors,
            abstract: fetch_abstract(doc, lang),
            copyright: fetch_copyright(doc, id),
            source: fetch_source(hit.hit[:url]),
            relation: fetch_relations(doc),
            place: [Bib::Place.new(city: "Tallinn")],
            ext: fetch_ext(doc, hit)
          )
        end

        private

        # @param doc [Mechanize::Page]
        # @return [Array<Relaton::Evs::Docidentifier>]
        def fetch_docid(doc)
          code = doc.at_xpath("//h1")&.text&.strip
          return [] unless code

          [Docidentifier.new(type: "EVS", content: code, primary: true)]
        end

        # @param doc [Mechanize::Page]
        # @param lang [String]
        # @return [Array<Relaton::Bib::Title>]
        def fetch_titles(doc, lang)
          title = doc.at_xpath("//h2[contains(@class,'product-title')]")&.text&.strip
          return [] unless title

          # `from_string` splits on " - " into intro/main and returns an Array.
          Bib::Title.from_string(title, lang, "Latn")
        end

        # The "Valid from" badge is the date the document entered into force.
        #
        # @param doc [Mechanize::Page]
        # @return [Relaton::Bib::Date, nil]
        def fetch_date(doc)
          badge = doc.at_xpath(
            "//div[contains(@class,'product-info-badge')][contains(., 'Valid from')]",
          )
          return unless badge

          d = badge.text.match(/(\d{2})\.(\d{2})\.(\d{4})/)
          return unless d

          Bib::Date.new(type: "published", at: "#{d[3]}-#{d[2]}-#{d[1]}")
        end

        # @return [Array<Relaton::Bib::Contributor>]
        def fetch_contributors
          role = Bib::Contributor::Role.new(type: "publisher")
          [Bib::Contributor.new(role: [role], organization: evs_org)]
        end

        # @param doc [Mechanize::Page]
        # @param lang [String]
        # @return [Array<Relaton::Bib::Abstract>]
        def fetch_abstract(doc, lang)
          scope = doc.at_xpath("//div[@id='tab-1']")&.text&.strip
          return [] unless scope

          [Bib::Abstract.new(content: scope, language: lang, script: "Latn")]
        end

        # @param doc [Mechanize::Page]
        # @param id [Pubid::Evs::Identifier, nil]
        # @return [Array<Bib::Copyright>]
        def fetch_copyright(doc, id)
          from = id&.root&.year&.to_s
          from ||= fetch_date(doc)&.at&.to_s&.slice(0, 4)
          return [] unless from

          owner = Bib::ContributionInfo.new(organization: evs_org)
          [Bib::Copyright.new(owner: [owner], from: from)]
        end

        # @param url [String]
        # @return [Array<Relaton::Bib::Uri>]
        def fetch_source(url)
          [Bib::Uri.new(type: "src", content: url)]
        end

        # The "Base Documents" group names the documents this record adopts:
        # the European document for a national adoption (`EN 18216:2026`), the
        # international document for a direct adoption. A double adoption
        # lists both in one text node ("ISO 14001:2026; EN ISO 14001:2026"),
        # so the pieces split on the semicolon. Each becomes an `adoptedFrom`
        # relation.
        #
        # @param doc [Mechanize::Page]
        # @return [Array<Relaton::Bib::Relation>]
        def fetch_relations(doc)
          group = doc.at_xpath(
            "//div[contains(@class,'product-ics-group')]" \
            "[div[contains(., 'Base Documents')]]",
          )
          return [] unless group

          bases(group).map do |base|
            Bib::Relation.new(
              type: "adoptedFrom",
              bibitem: ItemData.new(
                formattedref: Bib::Formattedref.new(content: base),
                type: "standard",
              ),
            )
          end
        end

        def bases(group)
          group.xpath("./a | ./text()").map(&:text)
               .flat_map { |t| t.split(";") }.map(&:strip)
               .reject(&:empty?).uniq
        end

        # @param doc [Mechanize::Page]
        # @return [Array<Relaton::Bib::ICS>]
        def fetch_ics(doc)
          doc.xpath(
            "//div[contains(@class,'product-group-heading')][contains(., 'ICS')]",
          ).each_with_object([]) do |heading, acc|
            heading.parent.xpath("./a").each do |a|
              code = a.text.strip[/^[\d.]+/]
              next if code.nil? || acc.any? { |ics| ics.code == code }

              isoics = Isoics.fetch code
              acc << Bib::ICS.new(code: code, text: isoics.description)
            end
          end
        end

        # @param doc [Mechanize::Page]
        # @param hit [Relaton::Evs::Hit]
        # @return [Relaton::Evs::Ext]
        def fetch_ext(doc, hit)
          Ext.new(
            doctype: fetch_doctype(hit.pubid),
            flavor: "evs",
            ics: fetch_ics(doc),
            structuredidentifier: fetch_structuredid(hit.pubid),
          )
        end

        # The shared ext grammar requires a doctype. The TS and TR faces of a
        # plain Estonian standard map to their document types; every other
        # form is a standard.
        #
        # @param id [Pubid::Evs::Identifier, nil]
        # @return [Relaton::Bib::Doctype]
        def fetch_doctype(id)
          evs_type = id&.evs_type if id&.respond_to?(:evs_type)
          case evs_type
          when "TS" then Bib::Doctype.new(content: "technical-specification")
          when "TR" then Bib::Doctype.new(content: "technical-report")
          else Bib::Doctype.new(content: "standard")
          end
        end

        # `#root` is the accessor that answers for every form: a national
        # adoption keeps the origin standard's number and part behind its
        # `base` chain.
        #
        # @param id [Pubid::Evs::Identifier, nil]
        # @return [Relaton::Evs::StructuredIdentifier]
        def fetch_structuredid(id)
          root = id&.root
          StructuredIdentifier.new(
            docnumber: root&.number&.to_s,
            partnumber: root&.part.to_s,
            agency: ["EVS"],
          )
        end

        # @return [Hash]
        def evs_org
          @evs_org ||= begin
            name = Bib::TypedLocalizedString.new(
              content: "Eesti Standardimis- ja Akrediteerimiskeskus",
            )
            abbr = Bib::TypedLocalizedString.new(content: "EVS")
            uri = Bib::Uri.new(content: "https://www.evs.ee")
            Bib::Organization.new(name: [name], abbreviation: abbr, uri: [uri])
          end
        end
      end
    end
  end
end
