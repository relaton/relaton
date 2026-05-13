# frozen_string_literal: true

require_relative "hit"

module Relaton
  module Jis
    class HitCollection < Core::HitCollection
      GH_URL = "https://raw.githubusercontent.com/relaton/relaton-data-jis/v2/"

      #
      # Initialize hit collection
      #
      # @param [String] text reference
      # @param [String, nil] year year
      # @param [Array<Hash>] result search results
      #
      def initialize(text, year = nil, result:)
        super text, year
        @array = result.map { |h| Hit.create h, self }
      end

      #
      # Find hit in collection
      #
      # @return [Relaton::Bib::ItemData, Array<String>]
      #
      def find
        ref_year = year || ref_parts[:year]
        if ref_year
          find_by_year ref_year
        else
          find_all_years
        end
      end

      def find_by_year(ref_year)
        missed_years = []
        @array.each do |hit|
          return hit.item if hit.eq? ref_parts, ref_year

          missed_years << hit.id_parts[:year] if hit.eq?(ref_parts)
        end
        missed_years
      end

      def find_all_years # rubocop:disable Metrics/AbcSize
        hits = @array.select { |hit| hit.eq? ref_parts }
        return [] if hits.empty?

        item = hits.max_by { |i| i.id_parts[:year].to_i }.item
        item_id = item.docidentifier.first.content
        parent = item.to_most_recent_reference
        hits.each do |hit|
          next if hit.hit[:id] == item_id

          parent.relation << create_relation(hit)
        end
        parent
      end

      def find_all_parts # rubocop:disable Metrics/AbcSize
        hits = @array.select { |hit| hit.eq? ref_parts, all_parts: true }
        item = hits.min_by { |i| i.id_parts[:part].to_i }.item.to_all_parts
        hits.each do |hit|
          next if hit.hit[:id] == item.docidentifier.first.content

          item.relation << create_relation(hit)
        end
        item
      end

      def create_relation(hit)
        docid = Docidentifier.new(
          content: hit.hit[:id], type: "JIS", primary: true,
        )
        bibitem = ItemData.new(
          formattedref: Bib::Formattedref.new(content: hit.hit[:id]), docidentifier: [docid],
        )
        Relation.new(type: "instanceOf", bibitem: bibitem)
      end

      #
      # Return parts of reference
      #
      # @return [Hash] hash with parts of reference
      #
      def ref_parts
        @ref_parts ||= parse_ref ref
      end

      #
      # Parse reference
      #
      # @param [String] ref reference
      #
      # @return [Hash] hash with parts of reference
      #
      def parse_ref(ref)
        %r{
          ^(?<code>\w+\s\w\s?\w+)
          (?:-(?<part>\w+))?
          (?::(?<year>\d{4}))?
          (?:/(?<expl>EXPL(?:ANATION)?)(?:\s(?<expl_num>\d+))?)?
          (?:/(?<amd>AMDENDMENT)(?:\s(?<amd_num>\d+)(?::(?<amd_year>\d{4}))?)?)?
        }x =~ ref
        { code: code, part: part, year: year, expl: expl, expl_num: expl_num,
          amd: amd, amd_num: amd_num, amd_year: amd_year }
      end
    end
  end
end
