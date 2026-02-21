module Relaton
  module Itu
    module DataParserR
      extend self

      TYPE_MAP = {
        "ITU-R Recommendations" => "recommendation",
        "ITU-R Questions" => "question",
        "ITU-R Reports" => "technical-report",
        "Handbooks" => "handbook",
        "ITU-R Resolutions" => "resolution",
      }.freeze

      #
      # Parse ITU-R document from search API result.
      #
      # @param result [Hash] single search result from the API
      #
      # @return [Relaton::Itu::ItemData] bibliographic item
      #
      def parse(result)
        doctype = fetch_doctype(result)
        return unless doctype

        Relaton::Itu::ItemData.new(
          docidentifier: fetch_docid(result), title: fetch_title(result),
          date: fetch_date(result), language: ["en"],
          source: fetch_source(result), script: ["Latn"],
          type: "standard", ext: Relaton::Itu::Ext.new(doctype: doctype, flavor: "itu"),
        )
      end

      # @param result [Hash]
      # @return [Array<Relaton::Bib::Docidentifier>]
      def fetch_docid(result)
        title = result["Title"].to_s
        id = title.match(/^(ITU-R\s+\S+)/)&.captures&.first
        return [] unless id

        id = id.sub(/\s*\(.*/, "")
        [Relaton::Bib::Docidentifier.new(type: "ITU", content: id, primary: true)]
      end

      # @param result [Hash]
      # @return [Array<Relaton::Bib::Title>]
      def fetch_title(result)
        title = result["Title"].to_s
        content = title.sub(/^[^:]+:\s*/, "").strip
        content = title unless content.length > 0
        [Relaton::Bib::Title.new(type: "main", content: content, language: "en", script: "Latn")]
      end

      # @param result [Hash]
      # @return [Array<Relaton::Bib::Date>]
      def fetch_date(result)
        prop = property(result, "Publication date")
        return [] unless prop

        date = parse_pub_date(prop)
        return [] unless date

        [Relaton::Bib::Date.new(type: "published", at: date)]
      end

      # @param result [Hash]
      # @return [Array<Relaton::Bib::Uri>]
      def fetch_source(result)
        locations = result["Locations"]
        return [] unless locations.is_a?(Array)

        pdf = locations.find { |l| l["Type"] == "pdf" }
        return [] unless pdf && pdf["RawHref"]

        [Relaton::Bib::Uri.new(type: "pdf", content: pdf["RawHref"])]
      end

      # @param result [Hash]
      # @return [Relaton::Itu::Doctype, nil]
      def fetch_doctype(result)
        type_value = property(result, "Type")
        mapped = TYPE_MAP[type_value]
        return unless mapped

        Doctype.new(type: mapped)
      end

      private

      # Find a property value from the result's Properties array.
      # @param result [Hash]
      # @param name [String]
      # @return [String, nil]
      def property(result, name)
        props = result["Properties"]
        return unless props.is_a?(Array)

        entry = props.find { |p| p["Title"] == name }
        entry&.[]("Value")
      end

      # Parse publication date string like "January, 2024" or "2024".
      # @param value [String]
      # @return [String, nil]
      def parse_pub_date(value)
        case value
        when /(\w+),?\s+(\d{4})/
          month = Date::MONTHNAMES.index($1)
          month ? "#{$2}-#{format('%02d', month)}" : $2
        when /(\d{4})/
          $1
        end
      end
    end
  end
end
