module Relaton
  module Ecma
    class DataParser
      include ParserCommon

      #
      # Initialize parser
      #
      # @param [Nokogiri::XML::Element] hit document hit
      # @param [Hash] errors error tracking hash
      #
      def initialize(hit, errors = {})
        @hit = hit
        @errors = errors
      end

      # @return [Array<Relaton::Ecma::ItemData>]
      def parse
        if @hit[:href]
          parse_standard
        else
          parse_memento
        end
      end

      private

      def parse_standard
        doc = PageFetcher.new.get(@hit[:href])
        parser = StandardParser.new(hit: @hit, doc: doc, errors: @errors)
        bib = parser.to_bib_hash
        bib[:contributor] = contributor
        items = [ItemData.new(**bib)]
        edition_parser = EditionParser.new(
          doc: doc, bib: bib, errors: @errors,
          translation_source: parser.translation_source
        )
        items + edition_parser.parse
      end

      def parse_memento
        parser = MementoParser.new(hit: @hit, errors: @errors)
        bib = parser.to_bib_hash
        bib[:contributor] = contributor
        [ItemData.new(**bib)]
      end
    end
  end
end
