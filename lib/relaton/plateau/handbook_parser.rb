# encoding: UTF-8

module Relaton
  module Plateau
    class HandbookParser < Parser
      def initialize(version:, entry:, doctype:)
        @version = version
        @entry = entry
        super entry["handbook"]
        @doctype = doctype
      end

      private

      def edition
        @edition ||= @version["title"].split.first.match(/[\d.]+/).to_s
      end

      def parse_docnumber
        "Handbook ##{@entry["slug"]} #{edition}"
      end

      def parse_abstract
        return [] unless @item["description"]

        @item["description"].split("<br />").filter_map do |part|
          text = part.strip
          next if text.empty?

          lang, script = detect_lang(text)
          create_abstract(text, lang, script)
        end
      end

      def parse_edition
        number = edition.match(/\d\.\d/)[0]
        Bib::Edition.new(content: edition, number: number)
      end

      def parse_date
        super << create_date(@version["date"].gsub(".", "-"))
      end

      def parse_source
        %w[pdf html].map do |type|
          next unless @version[type]

          create_link(@version[type], type)
        end.compact
      end

      def parse_ext
        strid = Bib::StructuredIdentifier.new(
          type: "Handbook", agency: ["PLATEAU"], docnumber: @entry["slug"], edition: edition
        )
        Ext.new(
          doctype: Doctype.new(content: @doctype),
          flavor: "plateau",
          structuredidentifier: [strid],
          filesize: @version["filesize"].to_i
        )
      end
    end
  end
end
