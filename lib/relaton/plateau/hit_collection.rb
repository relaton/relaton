require_relative "hit"

module Relaton
  module Plateau
    class HitCollection < Relaton::Core::HitCollection
      ENDPOINT = "https://raw.githubusercontent.com/relaton/relaton-data-plateau/v2/"

      # An edition suffix in either the canonical Japanese form (`第1.0版`) or the
      # legacy Latin form (`1.0`), stripped in #to_all_editions to derive the
      # edition-less family id from a relaton-bib docidentifier *string* (the
      # fetched document is not a pubid). Matching itself is done on pubid objects.
      EDITION_SUFFIX = / (?:第[\d.]+版|\d+\.\d+)$/

      def find
        @array = if pubid_ref
                   index.search(pubid_ref) do |row|
                     if all_editions?
                       # same document (type + number + annex), any edition
                       pubid_ref.matches?(row[:id], ignore: [:edition])
                     else
                       row[:id] == pubid_ref # a specific edition (pubid ==: type/number/annex/edition)
                     end
                   end.map { |row| Hit.new(row, self) }
                 else
                   [] # ref did not parse (unrecognized reference) -> no results
                 end
        self
      end

      def fetch_doc
        return unless any?

        all_editions? ? to_all_editions : first.item
      end

      def index
        @index ||= Relaton::Index.find_or_create(
          :plateau, url: "#{ENDPOINT}#{INDEXFILE}.zip", file: "#{INDEXFILE}.yaml",
          pubid_class: ::Pubid::Plateau::Identifier
        )
      end

      private

      # `#ref` (the raw query string, from Core::HitCollection) parsed into a
      # canonical Pubid::Plateau::Identifier (memoized), or nil if pubid can't
      # parse it. Canonical (`第1.0版`), edition-less (`#00`), and legacy Latin
      # (`#00 1.0`) references all parse — pubid normalizes Latin input to the
      # canonical id (metanorma/pubid #269) — so search accepts both forms. See
      # lib/relaton/plateau/CLAUDE.md.
      def pubid_ref
        return @pubid_ref if defined?(@pubid_ref)

        @pubid_ref = ::Pubid::Plateau.parse(ref)
      rescue StandardError
        @pubid_ref = nil
      end

      # A reference with no edition (`PLATEAU Handbook #00`, or any Technical
      # Report — TRs carry no edition) asks for all editions of the document.
      def all_editions?
        pubid_ref&.edition.nil?
      end

      def to_all_editions
        return first.item if size < 2

        bibitem = first.item
        relations = map do |h|
          Bib::Relation.new(type: "hasEdition", bibitem: h.item)
        end
        docid = bibitem.docidentifier.map do |d|
          Bib::Docidentifier.new(
            content: d.content.sub(EDITION_SUFFIX, ""), type: d.type, primary: d.primary
          )
        end
        ItemData.new(
          docidentifier: docid,
          docnumber: bibitem.docnumber.sub(EDITION_SUFFIX, ""),
          title: bibitem.title,
          contributor: bibitem.contributor,
          relation: relations
        )
      end
    end
  end
end
