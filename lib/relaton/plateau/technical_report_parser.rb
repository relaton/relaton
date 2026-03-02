module Relaton
  module Plateau
    class TechnicalReportParser < Parser
      def initialize(entry)
        @entry = entry
        super entry["technicalReport"]
      end

      private

      def parse_docnumber
        "Technical Report ##{@entry["slug"]} #{edition_number}"
      end

      def parse_abstract
        super << create_abstract(@item["subtitle"])
      end

      def parse_edition
        Bib::Edition.new(content: edition_number, number: edition_number)
      end

      def edition_number
        "1.0"
      end

      def parse_date
        date_str = @entry["date"].sub(/T.*/, "")
        super << create_date(date_str)
      end

      def parse_source
        super << create_link(@item["pdf"], "pdf")
      end

      def parse_keyword
        @entry["globalTags"]["nodes"].map do |tag|
          Bib::Keyword.new(taxon: [Bib::LocalizedString.new(content: tag["name"])])
        end
      end

      def parse_ext
        strid = Bib::StructuredIdentifier.new(
          type: "Technical Report", klass: parse_subdoctype,
          agency: ["PLATEAU"], docnumber: @entry["slug"]
        )
        Ext.new(
          doctype: Doctype.new(content: "technical-report"),
          subdoctype: parse_subdoctype,
          flavor: "plateau",
          structuredidentifier: [strid],
          filesize: @item["filesize"].to_i
        )
      end

      def parse_subdoctype
        @entry["technicalReportCategories"]["nodes"].dig(0, "name")
      end
    end
  end
end
