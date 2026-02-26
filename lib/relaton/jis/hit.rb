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
      # Check if hit matches reference
      #
      # @param [Hash] ref_parts parts of reference
      # @param [String, nil] year year
      # @param [Boolean] all_parts check all parts of reference
      #
      # @return [Boolean] true if hit matches reference
      #
      def eq?(ref_parts, year = nil, all_parts: false) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/PerceivedComplexity
        part_match?(ref_parts, all_parts) &&
          (year.nil? || year == id_parts[:year]) &&
          expl_match?(ref_parts) && amd_match?(ref_parts)
      end

      #
      # Return parts of document id
      #
      # @return [Hash] hash with parts of document id
      #
      def id_parts
        @id_parts ||= hit_collection.parse_ref hit[:id]
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

      def part_match?(ref_parts, all_parts)
        id_parts[:code].include?(ref_parts[:code]) &&
          (all_parts || ref_parts[:part].nil? ||
           ref_parts[:part] == id_parts[:part])
      end

      def expl_match?(ref_parts)
        (ref_parts[:expl].nil? || !id_parts[:expl].nil?) &&
          (ref_parts[:expl_num].nil? ||
           ref_parts[:expl_num] == id_parts[:expl_num])
      end

      def amd_match?(ref_parts) # rubocop:disable Metrics/AbcSize
        (ref_parts[:amd].nil? || !id_parts[:amd].nil?) &&
          (ref_parts[:amd_num].nil? ||
           ref_parts[:amd_num] == id_parts[:amd_num]) &&
          (ref_parts[:amd_year].nil? ||
           ref_parts[:amd_year] == id_parts[:amd_year])
      end
    end
  end
end
