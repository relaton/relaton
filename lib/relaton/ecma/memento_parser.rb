module Relaton
  module Ecma
    class MementoParser
      include ParserCommon

      ATTRS = %i[docidentifier title date source ext].freeze

      # @param [Nokogiri::XML::Element] hit document hit
      # @param [Hash] errors error tracking hash
      def initialize(hit:, errors: {})
        @hit = hit
        @errors = errors
      end

      # @return [Hash] bibliographic item attributes
      def to_bib_hash
        bib = default_bib_hash
        ATTRS.each { |a| bib[a] = send "fetch_#{a}" }
        bib
      end

      private

      # @return [Array<Relaton::Bib::Docidentifier>]
      def fetch_docidentifier
        code = "ECMA MEM/#{@hit.at('div[1]//p').text}"
        docid = super(code)
        @errors[:memento_docidentifier] &&= docid.empty?
        docid
      end

      # @return [Array<Relaton::Bib::Title>]
      def fetch_title
        year = @hit.at("div[1]//p").text
        content = "\"Memento #{year}\" for year #{year}"
        result = [Bib::Title.new(content: content, language: "en", script: "Latn")]
        @errors[:memento_title] &&= result.empty?
        result
      end

      # @return [Array<Relaton::Bib::Date>]
      def fetch_date
        date = @hit.at("div[2]//p").text
        on = Date.strptime(date, "%B %Y").strftime "%Y-%m"
        result = [Bib::Date.new(type: "published", at: on)]
        @errors[:memento_date] &&= result.empty?
        result
      end

      # @return [Array<Relaton::Bib::Uri>]
      def fetch_source
        result = @hit.xpath("./div/section/div/p/a").map do |a|
          Bib::Uri.new(type: "pdf", content: a[:href])
        end
        @errors[:memento_source] &&= result.empty?
        result
      end
    end
  end
end
