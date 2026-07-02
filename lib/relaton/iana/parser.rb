module Relaton
  module Iana
    class Parser
      #
      # Document parser initalization
      #
      # @param [Nokogiri::XML::Element] xml
      #
      def initialize(xml, rootdoc, errors = {})
        @xml = xml
        @rootdoc = rootdoc
        @errors = errors
      end

      #
      # Initialize document parser and run it
      #
      # @param [Nokogiri::XML::Element] xml
      #
      # @return [Relaton::Iana::ItemData, nil] bibliographic item
      #
      def self.parse(xml, rootdoc = nil, errors = {})
        new(xml, rootdoc, errors).parse
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
        result = [Bib::Title.new(content: content, language: "en", script: "Latn")]
        @errors[:title] &&= result.empty?
        result
      end

      #
      # Parse link
      #
      # @return [Array<Relaton::Bib::Uri>] link
      #
      def parse_source
        result = if @rootdoc then @rootdoc.source
                 elsif @xml[:id]
                   uri = URI.join "https://www.iana.org/assignments/", @xml[:id]
                   [Bib::Uri.new(type: "src", content: uri.to_s)]
                 else
                   []
                 end
        @errors[:source] &&= result.empty?
        result
      end

      #
      # Parse docidentifier
      #
      # @return [Arra<RelatonBib::DocumentIdentifier>] docidentifier
      #
      def parse_docid
        result = [Bib::Docidentifier.new(type: "IANA", content: pub_id, primary: true)]
        @errors[:docid] &&= result.empty?
        result
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
        id = @xml["id"].to_s
        @errors[:docnumber] &&= id.empty?
        dn + id
      end

      #
      # Parse date
      #
      # @return [Array<Relaton::Bib::Date>] date
      #
      def parse_date
        d = @xml.xpath("./xmlns:created|./xmlns:published|./xmlns:updated").map do |dt|
          Bib::Date.new(type: dt.name, at: dt.text)
        end
        result = d.none? && @rootdoc ? @rootdoc.date : d
        @errors[:date] &&= result.empty?
        result
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
