module Relaton
  module Arxiv
    #
    # Map the entry of an arXiv API Atom feed to a `Bib::ItemData`. Elements
    # are found by local name: Atom elements have the default namespace, and
    # the arXiv extensions (`arxiv:doi`, `arxiv:journal_ref`, …) their own.
    #
    class Parser
      ATTRS = %i[type fetched title docidentifier source date contributor
                 abstract version keyword note relation ext].freeze

      # The DOI prefix under which arXiv registers each e-print with DataCite.
      DOI_PREFIX = "10.48550/arXiv.".freeze

      ID_PATTERN = %r{\Ahttps?://arxiv\.org/abs/(?<id>.+?)(?:v(?<version>\d+))?\z}

      #
      # @param xml [String] the Atom feed
      # @return [Relaton::Bib::ItemData, nil] nil when the feed has no entry,
      #   or only arXiv's error entry (`<id>https://arxiv.org/api/errors#…`),
      #   which is how arXiv answers an id it rejects
      #
      def self.parse(xml)
        doc = Moxml.new.parse xml
        entry = doc.xpath("//*[local-name()='entry']").first
        return unless entry

        id = entry.children.detect { |n| n.is_a?(Moxml::Element) && n.name == "id" }
        match = id && ID_PATTERN.match(id.text.strip)
        new(entry, match).parse if match
      end

      # @param entry [Moxml::Element]
      # @param id [MatchData] the entry id matched by ID_PATTERN
      def initialize(entry, id)
        @entry = entry
        @id = id
      end

      # @return [Relaton::Bib::ItemData]
      def parse
        Bib::ItemData.new(**ATTRS.to_h { |a| [a, send("parse_#{a}")] })
      end

      private

      def children(name)
        @entry.children.select { |n| n.is_a?(Moxml::Element) && n.name == name }
      end

      def text(name, node = @entry)
        el = node.children.detect { |n| n.is_a?(Moxml::Element) && n.name == name }
        el && squeeze(el.text)
      end

      def squeeze(str)
        str.to_s.gsub(/\s+/, " ").strip
      end

      def bare_id = @id[:id]

      # An e-print a journal published is cited as an article; otherwise it
      # is a preprint.
      def parse_type
        text("journal_ref") ? "article" : "misc"
      end

      def parse_fetched = Date.today.to_s

      def parse_title
        title = text("title")
        title && !title.empty? ? [Bib::Title.new(type: "main", content: title)] : []
      end

      def parse_docidentifier
        versioned = "arXiv:#{bare_id}#{"v#{@id[:version]}" if @id[:version]}"
        [
          Bib::Docidentifier.new(type: "arXiv", content: versioned, primary: true),
          Bib::Docidentifier.new(type: "DOI", content: "#{DOI_PREFIX}#{bare_id}"),
        ]
      end

      def parse_source
        children("link").filter_map do |link|
          case [link["rel"], link["title"]]
          in ["alternate", _] then Bib::Uri.new(type: "src", content: link["href"])
          in ["related", "pdf"] then Bib::Uri.new(type: "pdf", content: link["href"])
          else nil
          end
        end
      end

      def parse_date
        %w[published updated].filter_map do |type|
          value = text(type)
          Bib::Date.new(type: type, at: value[0, 10]) if value && !value.empty?
        end
      end

      def parse_contributor
        children("author").filter_map do |author|
          name = text("name", author)
          next if name.nil? || name.empty?

          Bib::Contributor.new(
            person: create_person(name, author),
            role: [Bib::Contributor::Role.new(type: "author")],
          )
        end
      end

      def create_person(name, author)
        affiliation = author.children.filter_map do |n|
          next unless n.is_a?(Moxml::Element) && n.name == "affiliation"

          org = Bib::Organization.new(
            name: [Bib::TypedLocalizedString.new(content: squeeze(n.text))],
          )
          Bib::Affiliation.new(organization: org)
        end
        Bib::Person.new(
          name: Bib::FullName.new(completename: Bib::LocalizedString.new(content: name)),
          affiliation: affiliation,
        )
      end

      def parse_abstract
        summary = text("summary")
        summary && !summary.empty? ? [Bib::Abstract.new(content: summary)] : []
      end

      def parse_version
        @id[:version] ? [Bib::Version.new(content: @id[:version])] : []
      end

      # The categories, the primary first.
      def parse_keyword
        primary = children("primary_category").first&.[]("term")
        terms = children("category").map { |c| c["term"] }
        ([primary] + terms).compact.uniq.map do |term|
          Bib::Keyword.new(vocab: [Bib::LocalizedString.new(content: term)])
        end
      end

      def parse_note
        ref = text("journal_ref")
        ref ? [Bib::Note.new(type: "journal-ref", content: ref)] : []
      end

      # The journal article an e-print became, by the DOI arXiv records.
      def parse_relation
        doi = text("doi")
        return [] unless doi && !doi.empty?

        # An ItemData, not an ItemBase: the YAML serializer rejects an
        # ItemBase in a relation (Lutaml::Model::IncorrectModelError).
        docid = Bib::Docidentifier.new(type: "DOI", content: doi)
        [Bib::Relation.new(type: "hasManifestation",
                           bibitem: Bib::ItemData.new(docidentifier: [docid]))]
      end

      def parse_ext
        Bib::Ext.new(flavor: "arxiv")
      end
    end
  end
end
