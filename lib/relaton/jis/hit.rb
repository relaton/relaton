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

      #
      # Check if the hit matches the collection's reference.
      #
      # The candidate must be the same document type (so a plain standard query
      # never matches its amendments) and share series and number. Part is
      # compared only when the reference names a specific part and `all_parts`
      # is off. Year is filtered separately by {HitCollection}.
      #
      # @param [Boolean] all_parts match any part of the document
      #
      # @return [Boolean] true if the hit matches
      #
      def matches?(all_parts: false)
        cand = pubid
        return false unless cand && same_document?(cand)
        return true if all_parts || reference_partless?

        Array(cand.parts).map(&:to_s) == reference_parts
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

      # Same document type, series and number as the reference.
      def same_document?(cand)
        cand.instance_of?(reference.class) &&
          cand.series == reference.series &&
          cand.number.to_s == reference.number.to_s
      end

      def reference_partless?
        reference.parts.nil? || reference.parts.empty?
      end

      def reference_parts
        Array(reference.parts).map(&:to_s)
      end
    end
  end
end
