module Relaton
  module Plateau
    class TechnicalReportParser < Parser
      def initialize(entry, errors = {})
        @entry = entry
        super(entry["technicalReport"], errors)
      end

      private

      def parse_docnumber
        @errors[:tr_docnumber] &&= @entry["slug"].nil? || @entry["slug"].to_s.empty?
        "Technical Report ##{@entry["slug"]} #{edition_number}"
      end

      def parse_abstract
        if @item["subtitle"].nil? || @item["subtitle"].empty?
          @errors[:tr_abstract] &&= true
          return super
        end

        result = super << create_abstract(@item["subtitle"])
        @errors[:tr_abstract] &&= result.empty?
        result
      end

      def parse_edition
        result = Bib::Edition.new(content: edition_number, number: edition_number)
        result
      end

      def edition_number = "1.0"

      def parse_date
        if @entry["date"].nil? || @entry["date"].empty?
          @errors[:tr_date] &&= true
          return super
        end

        date_str = @entry["date"].sub(/T.*/, "")
        result = super << create_date(date_str)
        @errors[:tr_date] &&= result.empty?
        result
      end

      def parse_source
        if @item["pdf"].nil? || @item["pdf"].empty?
          @errors[:tr_source] &&= true
          return super
        end

        result = super << create_link(@item["pdf"], "pdf")
        @errors[:tr_source] &&= result.empty?
        result
      end

      def parse_keyword
        result = @entry["globalTags"]["nodes"].map do |tag|
          Bib::Keyword.new(vocab: Bib::LocalizedString.new(content: tag["name"]))
        end
        @errors[:tr_keyword] &&= result.empty?
        result
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
          filesize: filesize
        )
      end

      def filesize
        @errors[:tr_filesize] &&= @item["filesize"].nil?
        @item["filesize"].to_i
      end

      def parse_subdoctype
        result = @entry["technicalReportCategories"]["nodes"].dig(0, "name")
        @errors[:tr_subdoctype] &&= result.nil?
        result
      end
    end
  end
end
