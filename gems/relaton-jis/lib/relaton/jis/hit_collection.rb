# frozen_string_literal: true

require_relative "hit"

module Relaton
  module Jis
    class HitCollection < Core::HitCollection
      GH_URL = "https://raw.githubusercontent.com/relaton/relaton-data-jis/v2/"

      #
      # Initialize hit collection.
      #
      # Searches the pubid-based `index-v2` for every entry sharing the
      # reference's series and number (a supplement is filed under its base
      # number, so editions and amendments come back together). Narrowing to a
      # specific type/year/part happens later in {#find}.
      #
      # @param [Pubid::Jis::Identifier] pubid parsed reference
      #
      def initialize(pubid)
        super(pubid, pubid.year&.to_s)
        @array = index.search(pubid) { |row| same_base? row[:id] }
          .map { |row| Hit.new row, self }
          .sort_by { |hit| hit.pubid.to_s }
      end

      # @return [Pubid::Jis::Identifier] parsed reference
      def pubid
        ref
      end

      #
      # Find the best hit for the reference.
      #
      # @return [Relaton::Bib::ItemData, Array<Integer>] the matching item, or
      #   the list of available edition years when none match the requested year
      #
      def find
        if pubid.year
          find_by_year pubid.year
        else
          find_all_years
        end
      end

      def find_by_year(ref_year)
        missed_years = []
        @array.each do |hit|
          next unless hit.matches?

          return hit.item if hit.pubid.year.to_s == ref_year.to_s

          missed_years << hit.pubid.year
        end
        missed_years
      end

      # The main item is the latest edition of the requested type; every other
      # candidate sharing the series and number (older editions, amendments,
      # explanations) is attached as an `instanceOf` relation.
      def find_all_years
        editions = @array.select(&:matches?)
        return [] if editions.empty?

        item = editions.max_by { |hit| hit.pubid.year.to_i }.item
        attach_relations item.to_most_recent_reference,
                         item.docidentifier.first.content
      end

      # The lowest-numbered part becomes the all-parts umbrella; every candidate
      # sharing the series and number is attached as an `instanceOf` relation.
      def find_all_parts
        parts = @array.select { |hit| hit.matches? all_parts: true }
        lowest = parts.min_by { |hit| hit.pubid.parts.first.to_i }
        item = lowest.item.to_all_parts
        attach_relations item, item.docidentifier.first.content
      end

      # Attach every candidate except `skip_id` to `umbrella` as an `instanceOf`
      # relation and return the umbrella.
      def attach_relations(umbrella, skip_id)
        @array.each do |hit|
          next if hit.pubid.to_s == skip_id

          umbrella.relation << create_relation(hit)
        end
        umbrella
      end

      def create_relation(hit)
        id = hit.pubid.to_s
        docid = Docidentifier.new content: id, type: "JIS", primary: true
        bibitem = ItemData.new(
          formattedref: Bib::Formattedref.new(content: id),
          docidentifier: [docid],
        )
        Relation.new type: "instanceOf", bibitem: bibitem
      end

      # Index of pubid identifiers (`index-v2`), deserialized via `pubid_class`.
      def index
        @index ||= Relaton::Index.find_or_create(
          :jis,
          url: "#{GH_URL}#{INDEXFILE_V2}.zip",
          file: "#{INDEXFILE_V2}.yaml",
          pubid_class: ::Pubid::Jis::Identifier,
        )
      end

      private

      # Broad candidate filter: same series and number as the reference. For a
      # supplement (amendment/corrigendum/explanation) the document series and
      # number live on `base`, so compare against that.
      def same_base?(candidate)
        cand = base_of candidate
        ours = base_of pubid
        cand.series == ours.series && cand.number.to_s == ours.number.to_s
      end

      def base_of(identifier)
        supplement = identifier.respond_to?(:base) && identifier.base
        supplement || identifier
      end
    end
  end
end
