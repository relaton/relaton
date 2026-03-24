module Relaton
  module Ecma
    class EditionParser
      include ParserCommon

      # @param [Mechanize::Page] doc document page
      # @param [Hash] bib base bibliographic item attributes
      # @param [Hash] errors error tracking hash
      # @param [Array] translation_source precomputed translation sources
      def initialize(doc:, bib:, errors: {}, translation_source: [])
        @doc = doc
        @bib = bib
        @errors = errors
        @translation_source = translation_source
      end

      # @return [Array<Relaton::Ecma::ItemData>] editions
      def parse # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
        return [] unless @doc

        docid = @bib[:docidentifier]
        @doc.xpath('//div[@id="main"]/div[1]/div/main/article/div/div/standard/div/ul/li').map do |hit|
          bib = @bib.dup
          id, ed, bib[:date], vol = edition_id_parts hit.at("./span", "./a").text
          bib[:source] = edition_source(hit) + edition_translation_source(ed)
          next if ed.nil? || ed.empty?

          bib[:docidentifier] = id.nil? || id.empty? ? docid : fetch_docidentifier(id)
          @errors[:edition_docidentifier] &&= bib[:docidentifier].empty?
          bib[:edition] = Bib::Edition.new(content: ed)
          bib[:extent] = create_extent(vol)
          @errors[:edition_extent] &&= bib[:extent].nil?
          ItemData.new(**bib)
        end.compact
      end

      #
      # Parse edition and date
      #
      # @param [String] text identifier text
      #
      # @return [Array<String,nil,Array<Relaton::Bib::Date>>] edition and date
      #
      def edition_id_parts(text) # rubocop:disable Metrics/MethodLength
        %r{^
          (?<id>\w+(?:[\d-]+|\sTR/\d+)),?\s
          (?:Volume\s(?<vol>[\d.]+),?\s)?
          (?<ed>[\d.]+)(?:st|nd|rd|th)?\sedition
          (?:[,.]\s(?<dt>\w+\s\d+))?
        }x =~ text
        date = [dt].compact.map do |d|
          on = Date.strptime(d, "%B %Y").strftime("%Y-%m")
          Bib::Date.new(type: "published", at: on)
        end
        [id, ed, date, vol]
      end

      def edition_source(hit)
        es = { "src" => hit.at("./a"), "pdf" => hit.at("./span/a") }.map do |type, a|
          Bib::Uri.new(type: type, content: a[:href]) if a
        end.compact
        @errors[:edition_source] &&= es.empty?
        es
      end

      def create_extent(vol)
        return unless vol && !vol.empty?

        locality = Bib::Locality.new(type: "volume", reference_from: vol)
        [Bib::Extent.new(locality: [locality])]
      end

      private

      def edition_translation_source(edition)
        @translation_source.select { |s| s[:ed] == edition }.map { |s| s[:source] }
      end
    end
  end
end
