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

      def index
        @index ||= Relaton::Index.find_or_create(
          :IEC,
          url: "#{Hit::GHURL}#{INDEXFILE}.zip",
          file: "#{INDEXFILE}.yaml",
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

      # Keys pubid re-emits at a default value after `from_hash` but omits on a
      # fresh `parse` (a lutaml render_default asymmetry: a deserialized
      # attribute loses its using_default flag, so render_default: false no
      # longer suppresses it). Equality must ignore them so a deserialized index
      # row compares equal to the freshly-parsed query. Values are the
      # stringified defaults (see #stringify).
      LEAKING_DEFAULTS = { "publisher" => "IEC", "all_parts" => "false", "database" => "false" }.freeze

      # Map a flat exclude symbol to the lean to_hash key it removes (at every
      # nesting level). :type removes the polymorphic `_type` discriminator.
      EXCLUDE_KEYS = { year: "year", part: "part", subpart: "subpart", type: "_type" }.freeze

      # Compare pubids for matching, excluding specified fields.
      # @param row_pubid [Pubid::Iec::Identifier] pubid from index row
      # @return [Boolean]
      def pubid_matches?(row_pubid, exclude)
        return false unless row_pubid

        canonical_id(@ref, exclude) == canonical_id(row_pubid, exclude)
      end

      # Build-path-independent comparison key: the lean `to_hash` with keys and
      # scalars stringified, leaking defaults dropped, and excluded fields
      # removed at every nesting level. More robust than comparing attribute
      # objects, whose derived `type`/`stage` differ between a parsed identifier
      # (component object) and a deserialized one (nil/symbol) — at the top level
      # and inside `base_identifier`.
      def canonical_id(pubid, exclude)
        drop = exclude.filter_map { |e| EXCLUDE_KEYS[e] }
        prune(stringify(pubid.to_hash), drop)
      end

      # Stringify hash keys and scalar values so comparison ignores YAML scalar
      # typing (1 vs "1") and string/symbol key differences.
      def stringify(value)
        case value
        when Hash  then value.to_h { |k, v| [k.to_s, stringify(v)] }
        when Array then value.map { |v| stringify(v) }
        when nil   then nil
        else value.to_s
        end
      end

      # Recursively drop nil values, leaking defaults, and excluded keys.
      def prune(value, drop)
        case value
        when Hash
          value.each_with_object({}) do |(k, v), h|
            next if v.nil? || drop.include?(k) || LEAKING_DEFAULTS[k] == v

            h[k] = prune(v, drop)
          end
        when Array then value.map { |v| prune(v, drop) }
        else value
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
