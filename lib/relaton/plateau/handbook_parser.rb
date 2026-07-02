# encoding: UTF-8

module Relaton
  module Plateau
    class HandbookParser < Parser
      def initialize(version:, entry:, doctype:, errors: {})
        @version = version
        @entry = entry
        super(entry["handbook"], errors)
        @doctype = doctype
      end

      private

      def edition
        @edition ||= @version["title"].split.first.match(/[\d.]+/).to_s
      end

      def slug_number
        @slug_number ||= @entry["slug"]&.to_s&.split("_")&.first
      end

      def parse_docnumber
        @errors[:hb_docnumber] &&= @entry["slug"].nil? || @entry["slug"].to_s.empty?
        ["Handbook ##{slug_number}", edition].compact.join(" ")
      end

      def parse_abstract
        unless @item["description"]
          @errors[:hb_abstract] &&= true
          return []
        end

        result = @item["description"].split("<br />").filter_map do |part|
          text = part.strip
          next if text.empty?

          lang, script = detect_lang(text)
          create_abstract(text, lang, script)
        end
        @errors[:hb_abstract] &&= result.empty?
        result
      end

      def parse_edition
        if edition.nil? || edition.empty?
          @errors[:hb_edition] &&= true
          return
        end

        number = edition.match(/\d\.\d/)[0]
        result = Bib::Edition.new(content: edition, number: number)
        @errors[:hb_edition] &&= result.nil?
        result
      end

      def parse_date
        if @version["date"].nil? || @version["date"].empty?
          @errors[:hb_date] &&= true
          return super
        end

        result = super << create_date(@version["date"].gsub(".", "-"))
        @errors[:hb_date] &&= result.empty?
        result
      end

      def parse_source
        result = %w[pdf html].map do |type|
          next unless @version[type]

          create_link(@version[type], type)
        end.compact
        @errors[:hb_source] &&= result.empty?
        result
      end

      def parse_ext
        strid = Bib::StructuredIdentifier.new(
          type: "Handbook", agency: ["PLATEAU"], docnumber: slug_number, edition: edition
        )
        Ext.new(
          doctype: Doctype.new(content: @doctype),
          flavor: "plateau",
          structuredidentifier: [strid],
          filesize: filesize
        )
      end
      def filesize
        @errors[:hb_filesize] &&= @version["filesize"].nil?
        @version["filesize"].to_i
      end
    end
  end
end
