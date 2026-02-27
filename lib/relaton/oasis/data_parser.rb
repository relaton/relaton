module Relaton
  module Oasis
    # Parser for OASIS document.
    class DataParser
      include DataParserUtils

      #
      # Initialize parser.
      #
      # @param [Nokogiri::HTML::Element] node document node
      #
      def initialize(node)
        @node = node
      end

      def title
        @title ||= @node.at("./summary/div/h2").text
      end

      def text
        xpath = "./div/div/div[contains(@class, " \
                "'standard__grid--cite-as')]" \
                "/p[em or i or a or span]"
        @text ||= @node.at(xpath)&.text&.strip
      end

      #
      # Parse document.
      #
      # @return [ItemData] bibliographic item data
      #
      def parse # rubocop:disable Metrics/MethodLength
        ItemData.new(
          type: "standard",
          title: parse_title,
          docidentifier: parse_docid,
          source: parse_link,
          docnumber: parse_docnumber,
          date: parse_date,
          contributor: parse_contributor,
          abstract: parse_abstract,
          language: ["en"],
          script: ["Latn"],
          relation: parse_relation,
          ext: create_ext,
        )
      end

      #
      # Parse title.
      #
      # @return [Array<Bib::Title>] title
      #
      def parse_title
        [Bib::Title.new(type: "main", content: title, language: "en",
                        script: "Latn")]
      end

      #
      # Parse date.
      #
      # @return [Array<Bib::Date>] date
      #
      def parse_date
        @node.xpath("./summary/div/time[@class='standard__date']").map do |d|
          date_str = d.text.match(/\d{2}\s\w+\s\d{4}/).to_s
          date = Date.parse(date_str).to_s
          Bib::Date.new(at: date, type: "issued")
        end
      end

      #
      # Parse abstract.
      #
      # @return [Array<Bib::LocalizedMarkedUpString>] abstract
      #
      def parse_abstract
        c = @node.xpath(
          "./summary/div/div[@class='standard__description']/p",
        ).map { |a| a.text.gsub(/[\n\t]+/, " ").strip }.join("\n")
        return [] if c.empty?

        [Bib::LocalizedMarkedUpString.new(content: c, language: "en",
                                          script: "Latn")]
      end

      #
      # Parse editorial group as contributors.
      #
      # @return [Array<Bib::Contributor>] editorial group contributors
      #
      def parse_editorialgroup_contributor # rubocop:disable Metrics/MethodLength
        tcs = @node.xpath("./div[@class='standard__details']/a")
        return [] if tcs.empty?

        subdivisions = tcs.map do |a|
          name = [Bib::TypedLocalizedString.new(content: a.text.strip)]
          Bib::Subdivision.new(type: "technical-committee",
                               name: name)
        end
        org = Bib::Organization.new(
          name: [Bib::TypedLocalizedString.new(content: "OASIS")],
          subdivision: subdivisions,
        )
        desc = [Bib::LocalizedMarkedUpString.new(content: "committee")]
        role = Bib::Contributor::Role.new(
          type: "author", description: desc,
        )
        [Bib::Contributor.new(organization: org, role: [role])]
      end

      def parse_authorizer
        @node.xpath("./div[@class='standard__details']/a").map do |a|
          org = Bib::Organization.new(
            name: [Bib::TypedLocalizedString.new(content: a.text.strip)],
            uri: [Bib::Uri.new(type: "uri", content: a[:href])],
          )
          desc = [Bib::LocalizedMarkedUpString.new(content: "Committee")]
          role = Bib::Contributor::Role.new(type: "authorizer",
                                            description: desc)
          Bib::Contributor.new(organization: org, role: [role])
        end
      end

      def link_node
        xpath = "./div/div/div[contains(@class, " \
                "'standard__grid--cite-as')]" \
                "/p[strong or span/strong]/a"
        @link_node ||= @node.at(xpath)
      end

      #
      # Parse relation.
      #
      # @return [Array<Bib::Relation>] relation
      #
      def parse_relation
        xpath = "./div/div/div[contains(@class, " \
                "'standard__grid--cite-as')]" \
                "/p[strong or span/strong or b/span]"
        rels = @node.xpath(xpath)
        return [] unless rels.size > 1

        rels.map do |r|
          docid = DataPartParser.new(r).parse_docid
          bib = ItemData.new(formattedref: docid[0].content)
          Bib::Relation.new(type: "hasPart", bibitem: bib)
        end
      end

      #
      # Look for "Cite as" references.
      #
      # @return [Array<String>] document part references
      #
      def document_part_refs
        @node.css(
          ".standard__grid--cite-as > p > strong",
          "span.Refterm", "span.abbrev", "span.citationLabel > strong"
        ).map { |p| p.text.gsub(/^\[{1,2}|\]$/, "").strip }
      end

      def parse_link
        return [] if parts.size > 1

        links.map do |l|
          type = l[:href].match(/\.(\w+)$/)&.captures&.first
          type ||= "src"
          type.sub!("docx", "doc")
          type.sub!("html", "src")
          Bib::Uri.new(type: type, content: l[:href])
        end
      end

      def parts
        xpath = "./div/div/div[contains(@class, " \
                "'standard__grid--cite-as')]" \
                "/p[strong or span/strong]"
        @parts ||= @node.xpath(xpath)
      end

      def links
        l = @node.xpath("./div/div/div[1]/p[1]/a[@href]")
        l = @node.xpath("./div/div/div[1]/p[2]/a[@href]") if l.empty?
        l
      end

      #
      # Parse document number.
      #
      # @return [String] document number
      #
      def parse_docnumber
        parts = document_part_refs
        case parts.size
        when 0 then parse_spec title_to_docid(@node.at("./summary/div/h2").text)
        when 1 then parse_part parse_spec(parts[0])
        else parts_to_docid parts
        end
      end

      #
      # Create document identifier from parts references.
      #
      # @param [Array<String>] parts parts references
      #
      # @return [String] document identifier
      #
      def parts_to_docid(parts) # rubocop:disable Metrics/AbcSize
        id = parts[1..].each_with_object(parts[0].split("-")) do |part, acc|
          chunks = part.split "-"
          chunks.each.with_index do |chunk, idx|
            unless chunk.casecmp(acc[idx])&.zero?
              acc.slice!(idx..-1)
              break
            end
          end
        end.join("-")
        parse_part parse_spec(id)
      end

      #
      # Create document identifier from title.
      #
      # @param [String] title title
      #
      # @return [String] document identifier
      #
      def title_to_docid(title) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        abbrs = title.scan(/(?<=\()[^)]+(?=\))/)
        if abbrs.any?
          id = abbrs.map { |abbr| abbr.split.join("-") }.join "-"
          /(?:Version\s|v)(?<ver>[\d.]+)/ =~ title
          id += "-v#{ver}" if ver
          /(?<eb>ebXML|ebMS)/ =~ title
          id = "#{eb}-#{id}" if eb
          id
        else
          series_end = false
          title.sub(/\s\[OASIS\s\d+\]$/,
                    "").split(/[,:]?\s|-|(?<=[a-z])(?=[A-Z][a-z])/)
            .each_with_object([""]) do |word, acc|
              if word =~ /^v[\d.]+/
                acc << $MATCH.to_s
                series_end = true
              elsif word.match?(/^Version/)
                acc << "v"
                series_end = false
              elsif word.match?(/^\d|ebXML|ebMS/)
                series_end ? acc << word : acc[-1] += word
                series_end = true
              elsif word.match?(/^\w+$/) && word == word.upcase
                series_end ? acc << word : acc[-1] = word
                series_end = true
              elsif word.match?(/[A-Z]+[a-z]+/)
                series_end ? acc << word[0] : acc[-1] += word[0]
                series_end = false
              end
          end.join "-"
        end
      end

      #
      # Parse technology areas.
      #
      # @return [Array<String>] technology areas
      #
      def parse_technology_area
        super @node
      end
    end
  end
end
