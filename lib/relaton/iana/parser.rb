module Relaton
  module Iana
    class Parser
      #
      # Document parser initalization
      #
      # @param [Nokogiri::XML::Element] xml
      #
      def initialize(xml, rootdoc)
        @xml = xml
        @rootdoc = rootdoc
      end

      #
      # Initialize document parser and run it
      #
      # @param [Nokogiri::XML::Element] xml
      #
      # @return [Relaton::Iana::ItemData, nil] bibliographic item
      #
      def self.parse(xml, rootdoc = nil)
        new(xml, rootdoc).parse
      end

      #
      # Parse document
      #
      # @return [Relaton::Iana::ItemData, nil] bibliographic item
      #
      def parse # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
        return unless @xml

        Relaton::Iana::ItemData.new(
          type: "standard",
          language: ["en"],
          script: ["Latn"],
          title: parse_title,
          source: parse_source,
          docidentifier: parse_docid,
          docnumber: docnumber,
          date: parse_date,
          contributor: contributor,
        )
      end

      #
      # Parse title
      #
      # @return [Array<Relaton::Bib::Title>] title
      #
      def parse_title
        content = @xml.at("./xmlns:title")&.text || @xml[:id]
        [Bib::Title.new(content: content, language: "en", script: "Latn")]
      end

      #
      # Parse link
      #
      # @return [Array<Relaton::Bib::Uri>] link
      #
      def parse_source
        if @rootdoc then @rootdoc.source
        else
          uri = URI.join "https://www.iana.org/assignments/", @xml[:id]
          [Bib::Uri.new(type: "src", content: uri.to_s)]
        end
      end

      #
      # Parse docidentifier
      #
      # @return [Arra<RelatonBib::DocumentIdentifier>] docidentifier
      #
      def parse_docid
        [Bib::Docidentifier.new(type: "IANA", content: pub_id, primary: true)]
      end

      #
      # Create anchor
      #
      # @return [String] anchor
      #
      def anchor
        docnumber.upcase.gsub("/", "__")
      end

      #
      # Generate PubID
      #
      # @return [String] PubID
      #
      def pub_id
        "IANA #{docnumber}"
      end

      #
      # Create docnumber
      #
      # @return [String] docnumber
      #
      def docnumber
        dn = ""
        dn += "#{@rootdoc.docnumber}/" if @rootdoc
        dn + @xml["id"]
      end

      #
      # Parse date
      #
      # @return [Array<Relaton::Bib::Date>] date
      #
      def parse_date
        d = @xml.xpath("./xmlns:created|./xmlns:published|./xmlns:updated").map do |d|
          Bib::Date.new(type: d.name, at: d.text)
        end
        d.none? && @rootdoc ? @rootdoc.date : d
      end

      #
      # Create contributor
      #
      # @return [Array<Relaton::Bib::Contributor>] contributor
      #
      def contributor
        orgname = Bib::TypedLocalizedString.new(content: "Internet Assigned Numbers Authority")
        abbrev = Bib::LocalizedString.new(content: "IANA")
        org = Bib::Organization.new(name: [orgname], abbreviation: abbrev)
        role = Bib::Contributor::Role.new(type: "publisher")
        [Bib::Contributor.new(organization: org, role: [role])]
      end
    end
  end
end
