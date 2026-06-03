# frozen_string_literal: true

require "addressable/uri"
require_relative "hit"

module Relaton
  module Iec
    # Page of hit collection.
    class HitCollection < Core::HitCollection
      def_delegators :@array, :detect, :last, :max_by, :sort_by

      # @param exclude [Array<Symbol>] keys to exclude from comparison (e.g. :year, :part, :type)
      def search(exclude: [:year])
        @array = fetch_from_index exclude
        self
      end

      # @return [Relaton::Iec::ItemData, nil]
      def to_all_parts(r_year, opts = {}) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
        parts = @array.select { |h| h.part && (!r_year || h.hit[:id]&.date&.year&.to_s == r_year) }
        if opts[:publication_date_before] || opts[:publication_date_after]
          parts = parts.select { |h| Bibliography.send(:year_in_range?, h.hit[:id].date&.year.to_i, opts) }
        end
        hit = parts.min_by { |h| h.part.to_i }
        return @array.first&.item unless hit

        bibitem = hit.item
        all_parts_item = bibitem.to_all_parts
        others = parts.reject { |h| h.hit[:id] == hit.hit[:id] }
        others.sort_by { |h| part_sort_key(h.hit[:id]) }.each do |hi|
          code = hi.hit[:id].to_s
          bib = ItemData.new(
            formattedref: Bib::Formattedref.new(content: code),
            docidentifier: [Docidentifier.new(content: code, type: "IEC", primary: true)],
          )
          all_parts_item.relation << Relation.new(type: "partOf", bibitem: bib)
        end
        all_parts_item
      end

      private

      # Ascending sort key for part ordering, e.g. 61326-2-1 < 61326-2-6.
      # part/subpart are pubid Code components; coerce via to_s, missing → 0.
      def part_sort_key(pubid)
        sub = pubid.respond_to?(:subpart) ? pubid.subpart : nil
        [pubid.part.to_s.to_i, sub.to_s.to_i]
      end

      VALID_ID_KEYS = %i[
        publisher number year type vap amendments corrigendums copublisher part base fragment edition database sheet
      ]

      def index
        @index ||= Relaton::Index.find_or_create(
          :IEC,
          url: "#{Hit::GHURL}#{INDEXFILE}.zip",
          file: "#{INDEXFILE}.yaml",
          id_keys: VALID_ID_KEYS,
          pubid_class: ::Pubid::Iec::Identifier
        )
      end

      # Returns array of integers for sorting compound parts like "2-1", "2-6"
      # @param part [String, nil] part string e.g. "1", "2-1", "2-6"
      # @return [Array<Integer>] e.g. [2, 1] for "2-1", [6] for "6"
      def part_sort_key(part)
        return [] unless part

        part.to_s.split("-").map(&:to_i)
      end

      # Compare pubids for matching, excluding specified fields
      # @param row_pubid [Pubid::Iec::Identifier] pubid from index row
      # @return [Boolean]
      def pubid_matches?(row_pubid, exclude)
        return false unless row_pubid

        pubid_attrs(@ref, exclude) == pubid_attrs(row_pubid, exclude)
      end

      # Flat symbol-keyed attribute hash for pubid 2.x identifiers. Drops
      # :_type and :typed_stage; flattens :date Component to a :year string
      # so callers can exclude year by name as in pubid 1.x. Excluding
      # :type implies excluding :stage (the two are correlated via
      # typed_stage).
      def pubid_attrs(pubid, exclude = [])
        exclude = (exclude + [:stage]) if exclude.include?(:type)
        pubid.class.attributes.each_with_object({}) do |(name, _), h|
          next if %i[_type typed_stage].include?(name)
          next if exclude.include?(name)

          val = pubid.send(name)
          next if val.nil?

          if name == :date
            year = val.respond_to?(:year) ? val.year : nil
            h[:year] = year if year && !exclude.include?(:year)
          else
            h[name] = val
          end
        end
      end

      def fetch_from_index(exclude) # rubocop:disable Metrics/MethodLength
        return [] unless @ref

        index.search(@ref) do |row|
          pubid_matches?(row[:id], exclude)
        end.sort_by do |row|
          [row[:id].date&.year.to_i, *part_sort_key(row[:id].part)]
        end.map do |row|
          Hit.new(row, self)
        end
      end
    end
  end
end
