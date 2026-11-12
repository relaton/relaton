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

      # Canonical PLATEAU handbook edition label, e.g. "第3.0版" — the form
      # Pubid::Plateau parses. The Latinized #edition is kept for the structured
      # Bib::Edition/number and the ext structuredidentifier.
      def edition_label
        @edition_label ||= @version["title"].to_s[/第[\d.]+版/].to_s
      end

      # Volume label of the version title, as Pubid::Plateau renders it:
      # "本編" (main volume) or "本編＋付録" (main volume and appendix). Handbook
      # #00 edition 5.0 is published as both. ASCII "+" becomes "＋".
      def volume_label
        @version["title"].to_s[/第[\d.]+版[ 　]+(本編(?:[＋+]付録)?)/, 1]&.tr("+", "＋")
      end

      def slug_number
        @slug_number ||= mapped_docnumber&.[](/#(\S+)/, 1) ||
          @entry["slug"]&.to_s&.split("_")&.first
      end

      def parse_docnumber
        @errors[:hb_docnumber] &&= @entry["slug"].nil? || @entry["slug"].to_s.empty?
        mapped_docnumber ||
          ["Handbook ##{slug_number}", edition_label, volume_label].reject { |s| s.to_s.empty? }.join(" ")
      end

      # Part label of a split edition, e.g. "（公共活用編）". Editions 1-3 of
      # Handbook #11 were two documents each (relaton-plateau#13).
      def part_label
        @version["title"].to_s[/（[^（）]+活用編）/]
      end

      # The canonical docnumber of a split edition, mapped by pubid's
      # update_codes ("Handbook #11 第1.0版（公共活用編）" -> "Handbook #04
      # 第1.0版"), or nil for an edition that is not split.
      def mapped_docnumber
        return @mapped_docnumber if defined? @mapped_docnumber

        @mapped_docnumber = if part_label
                              slug = @entry["slug"]&.to_s&.split("_")&.first
                              raw = "PLATEAU Handbook ##{slug} #{edition_label}#{part_label}"
                              map_docnumber(raw)
                            end
      end

      def map_docnumber(raw)
        id = ::Pubid::Plateau.parse(raw).to_s
        id.delete_prefix("PLATEAU ") unless id == raw
      rescue ArgumentError, ::Pubid::Errors::Error => e
        Util.warn "Cannot map split edition `#{raw}`: #{e.message}"
        nil
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
