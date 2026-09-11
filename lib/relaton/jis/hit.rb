# frozen_string_literal: true

module Relaton
  module Jis
    class Hit < Core::Hit
      #
      # Create new hit
      #
      # @param [Hash] hit found hit
      # @param [Relaton::Jis::HitCollection] collection hit collection
      #
      # @return [Relaton::Jis::Hit] new hit
      #
      def self.create(hit, collection)
        new hit, collection
      end

      # The edition aspects. {HitCollection} picks the edition, so a match
      # ignores them. The reaffirmation mark `R` goes with the year:
      # `exclude(:year)` keeps it, and `JIS L 4107` must match
      # `JIS L 4107:2000R`.
      EDITION = %i[year reaffirmed].freeze

      #
      # Check if the hit matches the collection's reference.
      #
      # The candidate must be the same document type, so a plain standard
      # query never matches its amendments. The class check is explicit
      # because pubid's JIS `==` does not compare the class
      # (`JIS TR X 0014:1999 == JIS X 0014:1999`). The other aspects are
      # compared, except the edition, and the parts when `all_parts` is on.
      # This includes the base document of a supplement. The `SYMBOL` is
      # compared on a standard, but not on a supplement: pubid's supplement
      # `==` ignores it. {HitCollection#find_by_year} puts the exact printed id
      # first for that reason.
      #
      # @param [Boolean] all_parts match any part of the document
      #
      # @return [Boolean] true if the hit matches
      #
      def matches?(all_parts: false)
        return false unless pubid.instance_of?(reference.class)

        ignore = all_parts ? EDITION + [:parts] : EDITION
        reference.matches? pubid, ignore: ignore
      end

      #
      # The hit's pubid identifier. `index-v2` rows are already deserialized to
      # {Pubid::Jis::Identifier} via `pubid_class`; a Hash or String id is
      # converted for robustness.
      #
      # @return [Pubid::Jis::Identifier, nil] identifier, or nil when it cannot
      #   be built
      #
      def pubid
        return @pubid if defined? @pubid

        id = hit[:id]
        @pubid = case id
                 when Hash then ::Pubid::Jis::Identifier.from_hash id
                 when String then ::Pubid::Jis::Identifier.parse id
                 else id
                 end
      rescue StandardError
        Util.warn "Unable to create an identifier from `#{hit[:id]}`"
        @pubid = nil
      end

      # @return [Relaton::Jis::Item]
      def item
        @item ||= begin
          url = "#{HitCollection::GH_URL}#{hit[:file]}"
          resp = Net::HTTP.get_response URI(url)
          item = Item.from_yaml resp.body
          item.fetched = Date.today.to_s
          item
        end
      end

      private

      def reference
        hit_collection.pubid
      end
    end
  end
end
