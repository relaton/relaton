module Relaton
  module Oasis
    # Parser for OASIS part document.
    class DataPartParser
      include DataParserUtils

      #
      # Initialize parser.
      #
      # @param [Nokogiri::HTML::Element] node document node
      #
      def initialize(node, errors = {}, agent: nil)
        @node = node
        @errors = errors
        @agent = agent
      end

      def text
        return @text if @text

        sibling_xpath = "./strong/following-sibling::text()" \
                        "|./span[strong]/following-sibling::text()"
        if @node.at(sibling_xpath)
          nodes_xpath = "./strong/following-sibling::node()" \
                        "|./span[strong]/following-sibling::node()"
          @text = @node.xpath(nodes_xpath).text.strip
        else
          @text = @node.xpath("./following-sibling::p[1][em]").text.strip
        end
      end

      def title
        return @title if @title

        xpath = "./span[@class='citationTitle' " \
                "or @class='citeTitle']|./em|./i"
        t = @node.at(xpath)
        @title = if t
                   t.text
                 else
                   m = text.match(/(?<content>.+)\s(?:Edited|\d{2}\s\w+\d{4})/)
                   m ? m[:content] : text
                 end.strip
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
          abstract: parse_abstract,
          language: ["en"],
          script: ["Latn"],
          relation: parse_relation,
          contributor: parse_contributor,
          ext: create_ext,
        )
      end

      #
      # Parse title.
      #
      # @return [Array<Bib::Title>] title
      #
      def parse_title
        result = [Bib::Title.new(type: "main", content: title,
                                 language: "en", script: "Latn")]
        @errors[:part_title] &&= result.empty?
        result
      end

      #
      # Parse document number.
      #
      # @return [String] document number
      #
      def parse_docnumber
        ref = @node.at("./span/strong|./strong|./b/span")
        num = ref.text.match(/[^\[\]]+/).to_s
        id = parse_errata(num)
        # some part refs need "Pt" to distinguish from root doc
        id += "-Pt" if %w[CMIS-v1.1 DocBook-5.0 XACML-V3.0 mqtt-v3.1.1
                          OData-JSON-Format-v4.0].include?(id)
        result = parse_part parse_spec id
        @errors[:part_docnumber] &&= result.nil?
        result
      end

      #
      # Parse link.
      #
      # @return [Array<Bib::Uri>] link
      #
      def parse_link
        result = [Bib::Uri.new(type: "src", content: link_node[:href])]
        @errors[:part_link] &&= result.empty?
        result
      end

      #
      # Parse date.
      #
      # @return [Array<Bib::Date>] bibliographic dates
      #
      def parse_date
        match = text.match(/(?<on>\d{1,2}\s\w+\s\d{4})/)
        result = match ? [Bib::Date.new(at: Date.parse(match[:on]).to_s, type: "issued")] : []
        @errors[:part_date] &&= result.empty?
        result
      end

      def parse_abstract # rubocop:disable Metrics/MethodLength
        result = if page
                   xpath = "//p[preceding-sibling::p" \
                           "[starts-with(., 'Abstract')]][1]"
                   page.xpath(xpath).map do |p|
                     cnt = p.text.gsub(/[\r\n]+/, " ").strip
                     Bib::Abstract.new(
                       content: cnt, language: "en", script: "Latn",
                     )
                   end
                 else
                   []
                 end
        @errors[:part_abstract] &&= result.empty?
        result
      end

      #
      # Parse editorial group as contributors.
      #
      # @return [Array<Bib::Contributor>] editorial group contributors
      #
      def parse_editorialgroup_contributor # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        result = if page
                   xpath = "//p[preceding-sibling::p" \
                           "[starts-with(., 'Technical')]][1]//a"
                   tcs = page.xpath(xpath)
                   if tcs.empty?
                     []
                   else
                     subdivisions = tcs.map do |a|
                       name = [Bib::TypedLocalizedString.new(
                         content: a.text.strip,
                       )]
                       Bib::Subdivision.new(
                         type: "technical-committee", name: name,
                       )
                     end
                     org = Bib::Organization.new(
                       name: [Bib::TypedLocalizedString.new(
                         content: "OASIS",
                       )],
                       subdivision: subdivisions,
                     )
                     desc = [Bib::LocalizedMarkedUpString.new(
                       content: "committee",
                     )]
                     role = Bib::Contributor::Role.new(
                       type: "author", description: desc,
                     )
                     [Bib::Contributor.new(organization: org,
                                           role: [role])]
                   end
                 else
                   []
                 end
        @errors[:part_editorialgroup_contributor] &&= result.empty?
        result
      end

      #
      # Parse relation.
      #
      # @return [Array<Bib::Relation>] document relations
      #
      def parse_relation
        parser = DataParser.new(@node.at("./ancestor::details"), @errors, agent: @agent)
        fref = parser.parse_docid[0].content
        bib = ItemData.new(formattedref: Bib::Formattedref.new(content: fref))
        result = [Bib::Relation.new(type: "partOf", bibitem: bib)]
        @errors[:part_relation] &&= result.empty?
        result
      end

      def parse_authorizer # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        result = if page
                   xpath = "//p[preceding-sibling::p" \
                           "[starts-with(., 'Technical')]][1]//a"
                   page.xpath(xpath).map do |a|
                     org_name = a.text.gsub(/[\r\n]+/, " ").strip
                     org = Bib::Organization.new(
                       name: [Bib::TypedLocalizedString.new(
                         content: org_name,
                       )],
                       uri: [Bib::Uri.new(type: "uri",
                                          content: a[:href])],
                     )
                     desc = [Bib::LocalizedMarkedUpString.new(
                       content: "Committee",
                     )]
                     role = Bib::Contributor::Role.new(
                       type: "authorizer", description: desc,
                     )
                     Bib::Contributor.new(organization: org,
                                          role: [role])
                   end
                 else
                   []
                 end
        @errors[:part_authorizer] &&= result.empty?
        result
      end

      def link_node
        @link_node = @node.at("./a|./following-sibling::p[1]/a")
      end

      #
      # Parse technology area.
      #
      # @return [Array<String>] technology areas
      #
      def parse_technology_area
        result = super(@node.at("./ancestor::details"))
        @errors[:part_technology_area] &&= result.empty?
        result
      end
    end
  end
end
