module Relaton::Bipm
  module RawdataBipmMetrologia
    class ArticleParser
      ATTRS = %i[docidentifier title contributor date copyright abstract relation series
                 extent type source ext].freeze
      #
      # Create new parser and parse document
      #
      # @param [String] path path to XML file
      #
      # @return [Relaton::Bipm::ItemDate] document
      #
      def self.parse(path)
        doc = Nokogiri::XML(File.read(path, encoding: "UTF-8"))
        journal, volume, article = path.split("/")[-2].split("_")[1..]
        new(doc, journal, volume, article).parse
      end

      #
      # Initialize parser
      #
      # @param [Nokogiri::XML::Document] doc XML document
      # @param [String] journal journal
      # @param [String] volume volume
      # @param [String] article article
      #
      def initialize(doc, journal, volume, article)
        @doc = doc.at "/article"
        @journal = journal
        @volume = volume
        @article = article
        @meta = doc.at("/article/front/article-meta")
      end

      #
      # Create new document
      #
      # @return [Relaton::Bipm::ItemData] document
      #
      def parse
        attrs = ATTRS.to_h { |a| [a, send("parse_#{a}")] }
        ItemData.new(**attrs)
      end

      #
      # Parse docid
      #
      # @return [Array<Relaton::Bib::DocumentIdentifier>] array of document identifiers
      #
      def parse_docidentifier
        pubid = "#{journal_title} #{volume_issue_article}"
        primary_id = create_docidentifier pubid, "BIPM", true
        @meta.xpath("./article-id[@pub-id-type='doi']").each_with_object([primary_id]) do |id, m|
          m << create_docidentifier(id.text, id["pub-id-type"])
        end
      end

      #
      # Parse volume, issue and page
      #
      # @return [String] volume issue page
      #
      def volume_issue_article
        [@journal, @volume, @article].compact.join(" ")
      end

      # def article
      #   @meta.at("./article-id[@pub-id-type='manuscript']").text.match(/[^_]+$/).to_s
      # end

      #
      # Parse journal title
      #
      # @return [String] journal title
      #
      def journal_title
        @doc.at("./front/journal-meta/journal-title-group/journal-title").text
      end

      #
      # Create document identifier
      #
      # @param [String] id document id
      # @param [String] type id type
      # @param [Boolean, nil] primary is primary id
      #
      # @return [Relaton::Bib::Docidentifier] document identifier
      #
      def create_docidentifier(id, type, primary = nil)
        Relaton::Bib::Docidentifier.new content: id, type: type, primary: primary
      end

      #
      # Parse title
      #
      # @return [Array<Relaton::Bib::TypedTitleString>] array of title strings
      #
      def parse_title
        @meta.xpath("./title-group/article-title").map do |t|
          next if t.text.empty?

          Relaton::Bib::Title.new(content: t.inner_html, language: t[:"xml:lang"], script: "Latn")
        end.compact
      end

      #
      # Parse contributor
      #
      # @return [Array<Relaton::Bib::Contributor>] array of contributors
      #
      def parse_contributor
        @meta.xpath("./contrib-group/contrib").map do |c|
          role = Relaton::Bib::Contributor::Role.new(type: c[:"contrib-type"])
          attrs = { person: create_person(c), organization: create_organization(c), role: [role] }
          Relaton::Bib::Contributor.new(**attrs)
        end
      end

      def create_person(contrib)
        name = contrib.at("./name")
        return unless name

        Relaton::Bib::Person.new name: fullname(name), affiliation: affiliation(contrib)
      end

      def create_organization(contrib)
        org = contrib.at("./collab")
        return unless org

        name = Relaton::Bib::TypedLocalizedString.new(content: org.text)
        Relaton::Bib::Organization.new name: [name]
      end

      #
      # Parse affiliations
      #
      # @param [Nokogiri::XML::Element] contrib contributor element
      #
      # @return [Array<Relaton::Bib::Affiliation>] array of affiliations
      #
      def affiliation(contrib)
        contrib.xpath("./xref[@ref-type='aff']").map do |x|
          a = @meta.at("./contrib-group/aff[@id='#{x[:rid]}']") # /label/following-sibling::node()")
            parse_affiliation a
        end.compact
      end

      def parse_affiliation(aff)
        text = aff.xpath("text()|sup|sub").to_xml.split(",").map(&:strip).reject(&:empty?).join(", ")
        text = CGI::unescapeHTML(text)
        return if text.include?("Permanent address:") || text == "Germany" ||
          text.start_with?("Guest") || text.start_with?("Deceased") ||
          text.include?("Author to whom any correspondence should be addressed")

        args = {}
        institution = aff.at('institution')
        if institution
          name = institution.text
          return if name == "1005 Southover Lane"

          args[:subdivision] = parse_division(aff)
          args[:address] = parse_address(aff)
        else
          name = text
        end
        args[:name] = [Relaton::Bib::TypedLocalizedString.new(content: name)]
        org = Relaton::Bib::Organization.new(**args)
        Relaton::Bib::Affiliation.new(organization: org)
      end

      def parse_division(aff)
        div = aff.xpath("text()[following-sibling::institution]").text.gsub(/^\W*|\W*$/, "")
        return [] if div.empty?

        name = Relaton::Bib::TypedLocalizedString.new(content: div, language: "en", script: "Latn")
        [Relaton::Bib::Subdivision.new(name: [name])]
      end

      def parse_address(aff)
        address = []
        addr = aff.xpath("text()[preceding-sibling::institution]").text.gsub(/^\W*|\W*$/, "")
        address << addr unless addr.empty?
        country = aff.at('country')
        address << country.text if country && !country.text.empty?
        address = address.join(", ")
        return [] if address.empty?

        [Relaton::Bib::Address.new(formatted_address: address)]
      end

      #
      # Create full name
      #
      # @param [Nokogiri::XML::Element] contrib contributor element
      #
      # @return [Relaton::Bib::FullName] full name
      #
      def fullname(name)
        cname = [name.at("./given-names"), name.at("./surname")].compact.map(&:text).join(" ")
        completename = Relaton::Bib::LocalizedString.new content: cname, language: "en", script: "Latn"
        Relaton::Bib::FullName.new completename: completename
      end

      #
      # Parse forename
      #
      # @param [String] given_name given name
      #
      # @return [Array<Relaton::Bib::Forename>] array of forenames
      #
      # def forename(given_name) # rubocop:disable Metrics/MethodLength
      #   return [] unless given_name

      #   given_name.text.scan(/(\w+)(?:\s(\w)(?:\s|$))?/).map do |nm, int|
      #     if nm.size == 1
      #       name = nil
      #       init = nm
      #     else
      #       name = nm
      #       init = int
      #     end
      #     Relaton::Bib::Forename.new(content: name, language: ["en"], script: ["Latn"], initial: init)
      #   end
      # end

      #
      # Parse date
      #
      # @return [Array<Relaton::Bib::Date>] array of dates
      #
      def parse_date
        at = dates.min
        [Relaton::Bib::Date.new(type: "published", at: at)]
      end

      #
      # Parse date
      #
      # @yield [date, type] date and type
      #
      # @return [Array<String, Object>] string date or whatever block returns
      #
      def dates
        @meta.xpath("./pub-date").map do |d|
          month = date_part(d, "month")
          day = date_part(d, "day")
          date = "#{d.at('./year').text}-#{month}-#{day}"
          block_given? ? yield(date, d[:"pub-type"]) : date
        end
      end

      def date_part(date, type)
        part = date.at("./#{type}")&.text
        return "01" if part.nil? || part.empty?

        part.rjust(2, "0")
      end

      #
      # Parse copyright
      #
      # @return [Array<Relaton::Bib::Copyright>] array of copyright associations
      #
      def parse_copyright
        @meta.xpath("./permissions").each_with_object([]) do |l, m|
          from = l.at("./copyright-year")
          next unless from

          owner = l.at("./copyright-statement").text.split(" & ").map do |c|
            /(?<name>[A-z]+(?:\s[A-z]+)*)/ =~ c
            org_name = Relaton::Bib::TypedLocalizedString.new(content: name, language: "en", script: "Latn")
            org = Relaton::Bib::Organization.new name: [org_name]
            Relaton::Bib::ContributionInfo.new(organization: org)
          end
          m << Relaton::Bib::Copyright.new(owner: owner, from: from.text)
        end
      end

      #
      # Parse abstract
      #
      # @return [Array<Relaton::Bib::LocalizedMarkedUpString>] array of abstracts
      #
      def parse_abstract
        @meta.xpath("./abstract").map do |a|
          Relaton::Bib::LocalizedMarkedUpString.new(
            content: a.inner_html, language: a[:"xml:lang"], script: "Latn",
          )
        end
      end

      #
      # Parese relation
      #
      # @return [Array<Relaton::Bib::Relation>] array of document relations
      #
      def parse_relation
        rels = dates do |d, t|
          Relaton::Bib::Relation.new(type: "hasManifestation", bibitem: bibitem(d, t))
        end
        rels + parse_references
      end

      #
      # Parse back/ref-list references as "cites" relations
      #
      # @return [Array<Relaton::Bib::Relation>] array of "cites" relations
      #
      def parse_references
        @doc.xpath("./back/ref-list/ref").filter_map do |ref|
          citation = ref.at("./element-citation")
          next unless citation

          Relaton::Bib::Relation.new(type: "cites", bibitem: citation_bibitem(citation))
        end
      end

      #
      # Build bibitem from an element-citation
      #
      # @param [Nokogiri::XML::Element] citation element-citation node
      #
      # @return [Relaton::Bipm::ItemData] bibitem
      #
      def citation_bibitem(citation)
        attrs = {}
        doi = citation.at("./pub-id[@pub-id-type='doi']")
        if doi
          attrs[:docidentifier] = [Relaton::Bib::Docidentifier.new(content: doi.text, type: "doi")]
          attrs[:source] = [Relaton::Bib::Uri.new(content: "https://doi.org/#{doi.text}", type: "doi")]
        end
        source = citation.at("./source")
        if source
          attrs[:title] = [Relaton::Bib::Title.new(content: source.text)]
        end
        year = citation.at("./year")
        if year
          attrs[:date] = [Relaton::Bib::Date.new(type: "published", at: year.text)]
        end
        ItemData.new(**attrs)
      end

      #
      # Create bibitem
      #
      # @param [String] date
      # @param [String] type date type
      #
      # @return [Relaton::Bipm::BipmBibliographicItem] bibitem
      #
      def bibitem(date, type)
        dt = Relaton::Bib::Date.new(type: type, at: date)
        carrier = type == "epub" ? "online" : "print"
        medium = Relaton::Bib::Medium.new carrier: carrier
        ItemData.new title: parse_title, date: [dt], medium: medium
      end

      #
      # Parse series
      #
      # @return [Array<Relaton::Bib::Series>] array of series
      #
      def parse_series
        title = Relaton::Bib::Title.new(content: journal_title, language: "en", script: "Latn")
        [Relaton::Bib::Series.new(title: [title])]
      end

      #
      # Parse extent
      #
      # @return [Array<Relaton::Bib::Extent>] array of extents
      #
      def parse_extent
        locs = @meta.xpath("./volume|./issue|./fpage").map do |e|
          if e.name == "fpage"
            type = "page"
            to = @meta.at("./lpage")&.text
          else
            type = e.name
          end
          Relaton::Bib::Locality.new type: type, reference_from: e.text, reference_to: to
        end
        [Relaton::Bib::Extent.new(locality: locs)]
        # %w[volume issue page].map.with_index do |t, i|
        #   Relaton::Bib::Locality.new t, volume_issue_page[i]
        # end
      end

      def parse_type
        "article"
      end

      def parse_doctype
        Doctype.new content: "article"
      end

      def parse_source
        @meta.xpath("./article-id[@pub-id-type='doi']").each_with_object([]) do |l, a|
          url = "https://doi.org/#{l.text}"
          a << Relaton::Bib::Uri.new(content: url, type: "src")
          a << Relaton::Bib::Uri.new(content: url, type: "doi")
        end
      end

      def parse_ext
        Ext.new doctype: parse_doctype
      end
    end
  end
end
