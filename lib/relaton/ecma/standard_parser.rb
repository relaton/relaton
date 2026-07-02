module Relaton
  module Ecma
    class StandardParser
      include ParserCommon

      ATTRS = %i[docidentifier title date source abstract relation edition ext].freeze

      # @param [Nokogiri::XML::Element] hit document hit
      # @param [Mechanize::Page] doc fetched document page
      # @param [Hash] errors error tracking hash
      def initialize(hit:, doc:, errors: {})
        @hit = hit
        @doc = doc
        @errors = errors
      end

      # @return [Hash] bibliographic item attributes
      def to_bib_hash
        bib = default_bib_hash
        ATTRS.each { |a| bib[a] = send "fetch_#{a}" }
        bib
      end

      # @return [Array] precomputed translation sources
      def translation_source
        @translation_source ||= parse_translation_source
      end

      # @return [Array<Relaton::Bib::Docidentifier>]
      def fetch_docidentifier
        result = super(@hit.text)
        @errors[:standard_docidentifier] &&= result.empty?
        result
      end

      # @return [Array<Relaton::Bib::Title>]
      def fetch_title
        result = @doc.xpath('//p[@class="ecma-item-short-description"]').map do |t|
          Bib::Title.new(content: t.text.strip, language: "en", script: "Latn")
        end
        @errors[:standard_title] &&= result.empty?
        result
      end

      # @return [Array<Relaton::Bib::LocalizedMarkedUpString>]
      def fetch_abstract
        content = @doc.xpath('//div[@class="ecma-item-content"]/p').map do |a|
          a.text.strip.squeeze(" ").gsub("\r\n", "")
        end.join "\n"
        return [] if content.empty?

        result = [Bib::Abstract.new(content: content, language: "en", script: "Latn")]
        @errors[:standard_abstract] &&= result.empty?
        result
      end

      # @return [Array<Relaton::Bib::Date>]
      def fetch_date
        result = @doc.xpath('//p[@class="ecma-item-edition"]').map do |d|
          date = d.text.split(", ").last
          Bib::Date.new type: "published", at: date
        end
        @errors[:standard_date] &&= result.empty?
        result
      end

      # @return [Array<Relaton::Bib::Uri>]
      def fetch_source # rubocop:disable Metrics/AbcSize
        source = []
        source << Bib::Uri.new(type: "src", content: @hit[:href]) if @hit[:href]
        ref = @doc.at('//div[@class="ecma-item-content-wrapper"]/span/a',
                      '//div[@class="ecma-item-content-wrapper"]/a')
        source << Bib::Uri.new(type: "pdf", content: ref[:href]) if ref
        result = source + edition_translation_source(fetch_edition_content)
        @errors[:standard_source] &&= result.empty?
        result
      end

      # @return [Array<Relaton::Bib::Relation>]
      def fetch_relation # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity
        edition_parser = EditionParser.new(doc: @doc, bib: {}, errors: @errors)
        result = @doc.xpath("//ul[@class='ecma-item-archives']/li").filter_map do |rel|
          ref, ed, date, vol = edition_parser.edition_id_parts rel.at("span").text
          next if ed.nil? || ed.empty?

          docid = Bib::Docidentifier.new(type: "ECMA", content: ref, primary: true)
          source = rel.xpath("span/a").map { |l| Bib::Uri.new type: "pdf", content: l[:href] }
          edition = Bib::Edition.new content: ed
          extent = edition_parser.create_extent(vol)
          @errors[:standard_relation_extent] &&= extent.nil?
          bibitem = ItemData.new(
            docidentifier: [docid], formattedref: Bib::Formattedref.new(content: ref), date: date, edition: edition,
            source: source, extent: extent
          )
          Bib::Relation.new(type: "updates", bibitem: bibitem)
        end
        @errors[:standard_relation] &&= result.empty?
        result
      end

      # @return [Relaton::Bib::Edition, nil]
      def fetch_edition
        cnt = fetch_edition_content
        result = Bib::Edition.new(content: cnt) if cnt && !cnt.empty?
        @errors[:standard_edition] &&= result.nil?
        result
      end

      private

      def fetch_edition_content
        @doc.at('//p[@class="ecma-item-edition"]')&.text&.match(/^\d+(?=(?:st|nd|th|rd))/)&.to_s
      end

      def edition_translation_source(edition)
        translation_source.select { |s| s[:ed] == edition }.map { |s| s[:source] }
      end

      def parse_translation_source
        return [] unless @doc

        @doc.xpath("//h2[.='Translations']/following-sibling::ul/li").map do |l|
          a = l.at("span/a")
          id = l.at("span").text
          %r{\w+[\d-]+,\s(?<lang>\w+)\sversion,\s(?<ed>[\d.]+)(?:st|nd|rd|th)\sedition} =~ id
          case lang
          when "Japanese"
            { ed: ed, source: Bib::Uri.new(type: "pdf", language: "ja", script: "Jpan", content: a[:href]) }
          end
        end.compact
      end
    end
  end
end
