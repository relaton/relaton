module Relaton
  module Isbn
    #
    # OpenLibrary document parser.
    #
    class Parser
      ATTRS = %i[fetched title docidentifier source contributor date place ext].freeze

      def initialize(doc)
        @doc = doc
      end

      def self.parse(doc)
        new(doc).parse
      end

      def parse
        args = ATTRS.each_with_object({}) { |a, h| h[a] = send(a) }
        Bib::ItemData.new(**args)
      end

      private

      def fetched = Date.today.to_s

      def title
        t = [Bib::Title.new(content: @doc["data"]["title"], type: "main")]
        if @doc["data"]["subtitle"]
          t << Bib::Title.new(content: @doc["data"]["subtitle"], type: "subtitle")
        end
        t
      end

      def docidentifier
        isbn = @doc["details"]["bib_key"].split(":").last
        [Bib::Docidentifier.new(content: isbn, type: "ISBN", primary: true)]
      end

      def source
        [Bib::Uri.new(content: @doc["recordURL"], type: "src")]
      end

      def contributor
        create_authors + creaate_publishers
      end

      def create_authors
        @doc["data"]["authors"].map do |a|
          name = Bib::FullName.new(
            completename: Bib::LocalizedString.new(content: a["name"]),
          )
          person = Bib::Person.new(
            name: name,
            uri: a["url"] ? [Bib::Uri.new(content: a["url"])] : [],
          )
          Bib::Contributor.new(
            person: person,
            role: [Bib::Contributor::Role.new(type: "author")],
          )
        end
      end

      def creaate_publishers
        @doc["data"]["publishers"].map do |p|
          org = Bib::Organization.new(
            name: [Bib::TypedLocalizedString.new(content: p["name"])],
          )
          Bib::Contributor.new(
            organization: org,
            role: [Bib::Contributor::Role.new(type: "publisher")],
          )
        end
      end

      def date
        @doc["publishDates"].map { Bib::Date.new type: "published", at: _1 }
      end

      def place
        @doc["data"]["publish_places"]&.map { Bib::Place.new city: _1["name"] }
      end

      def ext
        Bib::Ext.new(flavor: "isbn")
      end
    end
  end
end
