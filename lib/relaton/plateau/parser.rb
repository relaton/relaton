module Relaton
  module Plateau
    # Base class for Plateau parsers
    class Parser
      ATTRIS = %i[docidentifier docnumber title abstract depiction edition type
                  date source contributor keyword ext].freeze

      def initialize(item, errors = {})
        @item = item
        @errors = errors
      end

      def parse
        args = ATTRIS.each_with_object({}) do |attr, hash|
          hash[attr] = send("parse_#{attr}")
        end
        ItemData.new(**args)
      end

      private

      def parse_docidentifier
        result = [create_docid("PLATEAU #{parse_docnumber}")]
        @errors[:parse_docidentifier] &&= result.empty?
        result
      end

      def parse_docnumber; end

      def create_docid(id)
        Bib::Docidentifier.new(type: "PLATEAU", content: id, primary: true)
      end

      def create_abstract(content, lang = "ja", script = "Jpan")
        Bib::Abstract.new(content: content, language: lang, script: script)
      end

      def detect_lang(text)
        if text&.match?(/[\p{Han}\p{Katakana}\p{Hiragana}]/)
          ["ja", "Jpan"]
        else
          ["en", "Latn"]
        end
      end

      def parse_title
        lang, script = detect_lang(@item["title"])
        result = [create_title(@item["title"], lang, script)]
        @errors[:title] &&= result.empty?
        result
      end

      def create_title(title, lang, script)
        Bib::Title.new(type: "main", content: title, language: lang, script: script)
      end

      def parse_abstract; [] end

      def parse_depiction
        image_ext = @item["thumbnail"]["mediaItemUrl"].split(".").last
        mimetype = "image/"
        mimetype += image_ext == "jpg" ? "jpeg" : image_ext
        src = "https://www.mlit.go.jp/#{@item["thumbnail"]["mediaItemUrl"]}"
        image = Bib::Image.new(src: src, mimetype: mimetype)
        result = Bib::Depiction.new(scope: "cover", image: [image])
        @errors[:parse_depiction] &&= result.nil?
        [result]
      end

      def parse_edition; raise "Not implemented" end
      def parse_type; "standard" end
      def parse_date; [] end
      def parse_source; [] end

      def parse_contributor
        name = [
          Bib::TypedLocalizedString.new(content: "国土交通省", language: "ja", script: "Jpan"),
          Bib::TypedLocalizedString.new(
            content: "Japanese Ministry of Land, Infrastructure, Transport and Tourism",
            language: "en", script: "Latn"
          ),
        ]
        org = Bib::Organization.new(name: name, abbreviation: Bib::LocalizedString.new(content: "MLIT"))
        result = [Bib::Contributor.new(organization: org, role: [Bib::Contributor::Role.new(type: "publisher")])]
        @errors[:parse_contributor] &&= result.empty?
        result
      end

      def create_date(date, type = "published")
        Bib::Date.new(type: type, at: date)
      end

      def create_link(url, type)
        Bib::Uri.new(type: type, content: url)
      end

      def parse_keyword; [] end
      def parse_ext; raise "Not implemented" end
    end
  end
end
