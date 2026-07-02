require_relative "hit"

module Relaton
  module Plateau
    class HitCollection < Relaton::Core::HitCollection
      ENDPOINT = "https://raw.githubusercontent.com/relaton/relaton-data-plateau/v2/"

      def find
        @array = index.search do |row|
          if all_editions?
            row[:id].sub(/ \d+\.\d+$/, "") == @ref
          else
            row[:id] == @ref
          end
        end.map { |row| Hit.new(row, self) }
        self
      end

      def fetch_doc
        return unless any?

        all_editions? ? to_all_editions : first.item
      end

      def index
        @index ||= Relaton::Index.find_or_create(
          :plateau, url: "#{ENDPOINT}#{INDEXFILE}.zip", file: "#{INDEXFILE}.yaml"
        )
      end

      private

      def all_editions?
        @ref.match?(/ #\d+$/)
      end

      def to_all_editions
        return first.item if size < 2

        bibitem = first.item
        relations = map do |h|
          Bib::Relation.new(type: "hasEdition", bibitem: h.item)
        end
        docid = bibitem.docidentifier.map do |d|
          Bib::Docidentifier.new(
            content: d.content.sub(/ \d+\.\d+$/, ""), type: d.type, primary: d.primary
          )
        end
        ItemData.new(
          docidentifier: docid,
          docnumber: bibitem.docnumber.sub(/ \d+\.\d+$/, ""),
          title: bibitem.title,
          contributor: bibitem.contributor,
          relation: relations
        )
      end
    end
  end
end
