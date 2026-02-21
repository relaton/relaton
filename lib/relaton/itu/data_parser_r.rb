module Relaton
  module Itu
    module DataParserR
      extend self

      #
      # Parse ITU-R document.
      #
      # @param [Mechanize::Page] doc mechanize page
      # @param [String] url document url
      # @param [String] type document type
      #
      # @return [Relaton::Itu::ItemData] bibliographic item
      #
      def parse(doc, url, type)
        Relaton::Itu::ItemData.new(
          docidentifier: fetch_docid(doc), title: fetch_title(doc),
          abstract: fetch_abstract(doc), date: fetch_date(doc), language: ["en"],
          source: fetch_source(url), script: ["Latn"], status: fetch_status(doc),
          type: "standard", ext: Relaton::Itu::Ext.new(doctype: fetch_doctype(type))
        )
      end

      # @param doc [Mechanize::Page]
      # @return [Array<Relaton::Bib::Docidentifier>]
      def fetch_docid(doc)
        id = doc.at('//div[@id="idDocSetPropertiesWebPart"]/h2').text.match(/^R-\w+-([^-]+(?:-\d{1,3})?)/)[1]
        [Relaton::Bib::Docidentifier.new(type: "ITU", content: "ITU-R #{id}", primary: true)]
      end

      # @param doc [Mechanize::Page]
      # @return [Array<Relaton::Bib::Title>]
      def fetch_title(doc)
        content = doc.at('//h3[.="Title"]/parent::td/following-sibling::td[2]').text
        [Relaton::Bib::Title.new(type: "main", content: content, language: "en", script: "Latn")]
      end

      # @param doc [Mechanize::Page]
      # @return [Array<Relaton::Bib::LocalizedMarkedUpString>]
      def fetch_abstract(doc)
        doc.xpath('//h3[.="Observation"]/parent::td/following-sibling::td[2]').map do |a|
          c = a.text.strip
          Relaton::Bib::LocalizedMarkedUpString.new(content: c, language: "en", script: "Latn") unless c.empty?
        end.compact
      end

      # @param doc [Mechanize::Page]
      # @return [Array<Relaton::Bib::Date>]
      def fetch_date(doc)
        dates = []
        date = doc.at('//h3[.="Approval_Date"]/parent::td/following-sibling::td[2]',
                      '//h3[.="Approval date"]/parent::td/following-sibling::td[2]',
                      '//h3[.="Approval year"]/parent::td/following-sibling::td[2]')
        dates << parse_date(date.text, "confirmed") if date

        date = doc.at('//h3[.="Version year"]/parent::td/following-sibling::td[2]')
        dates << parse_date(date.text, "updated") if date
        date = doc.at('//div[@id="idDocSetPropertiesWebPart"]/h2').text.match(/(?<=-)(19|20)\d{2}/)
        dates << parse_date(date.to_s, "published") if date
        dates
      end

      # @param date [String]
      # @param type [String]
      # @return [Relaton::Bib::Date]
      def parse_date(date, type)
        d = case date
            when /(\d{4})(\d{2})/ then "#{$1}-#{$2}"
            when %r{(\d{1,2})/(\d{1,2})/(\d{4})} then "#{$3}-#{$1}-#{$2}"
            else date
            end
        Relaton::Bib::Date.new(type: type, at: d)
      end

      # @param url [String]
      # @return [Array<Relaton::Bib::Uri>]
      def fetch_source(url)
        [Relaton::Bib::Uri.new(type: "src", content: url)]
      end

      # @param doc [Mechanize::Page]
      # @return [Relaton::Bib::Status, nil]
      def fetch_status(doc)
        s = doc.at('//h3[.="Status"]/parent::td/following-sibling::td[2]')
        return unless s

        Relaton::Bib::Status.new(stage: Relaton::Bib::Status::Stage.new(content: s.text))
      end

      def fetch_doctype(type)
        Doctype.new(type: type)
      end
    end
  end
end
