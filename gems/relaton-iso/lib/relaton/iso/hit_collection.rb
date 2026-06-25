# frozen_string_literal: true

require_relative "hit"

module Relaton
  module Iso
    # Page of hit collection.
    class HitCollection < Relaton::Core::HitCollection
      ENDPOINT = "https://raw.githubusercontent.com/relaton/relaton-data-iso/v2/"

      def opts
        @opts ||= {}
      end

      # Maps the legacy 1.x exclude symbols to their pubid 2.x attribute
      # names. The public excludings API still uses :year/:iteration for
      # backwards compatibility with existing call sites and specs.
      LEGACY_EXCLUDE_MAP = { year: :date, iteration: :stage_iteration }.freeze
      private_constant :LEGACY_EXCLUDE_MAP

      def translate_excludings(attrs)
        out = attrs.map { |a| LEGACY_EXCLUDE_MAP[a] || a }
        # Excluding :stage implies excluding :typed_stage too — the two
        # carry overlapping data and their default-published values can
        # differ in trivia (e.g. original_abbr "" vs nil), so leaving
        # typed_stage in the comparison breaks otherwise-equal matches.
        out << :typed_stage if out.include?(:stage) && !out.include?(:typed_stage)
        out
      end

      def ref_pubid_no_year
        @ref_pubid_no_year ||=
          if ref.base_identifier
            ref.dup.tap { |r| r.base_identifier = r.base_identifier.exclude(:date) }
          else
            ref.exclude(:date)
          end
      end

      def ref_pubid_excluded
        return @ref_pubid_excluded if defined? @ref_pubid_excluded

        ref_excludings = translate_excludings(excludings) + [:all_parts]
        @ref_pubid_excluded ||= ref_pubid_no_year.exclude(*ref_excludings)
      end

      #
      # Find all the entries that match the given reference.
      #
      # @return [Array<Relaton::Iso::Hit>] hits
      #
      def find # rubocop:disable Metrics/AbcSize
        # Pass `ref` (a Pubid::Identifier, not a String) so the index can
        # narrow candidates by number via binary search before applying the
        # block, instead of a full O(n) scan of every row. Every row's `:id`
        # is already a Pubid::Identifier — Relaton::Index deserialized it via
        # the `pubid_class` passed in `#index` — so `pubid_match?` compares
        # Pubid to Pubid directly.
        @array = index.search(ref) do |row|
          pubid_match?(row[:id])
        end.map { |row| Hit.new row, self }
        # An all-parts query drops :part from the match, so multiple rows can
        # resolve to the same pubid; collapse them so each part appears once.
        @array.uniq! { |h| h.pubid.to_s } if ref.root.all_parts
        # Most-recent first (pubid string desc ~ year desc), then float
        # published-stage ids above drafts. An undated query excludes :stage
        # when matching, so a future draft (e.g. ISO/AWI) matches alongside the
        # published edition; without this the draft would sort first lexically
        # ("ISO/AWI …" > "ISO …") and be returned by fetch_doc's `first`. The
        # index id carries no lifecycle status, so the parsed stage is the only
        # signal available here. partition is stable, preserving the year order
        # within each group.
        @array.sort_by! { |h| h.pubid.to_s }.reverse!
        published, drafts = @array.partition do |h|
          h.pubid && default_published_stage?(h.pubid)
        end
        @array = published + drafts
        self
      end

      def pubid_match?(pubid)
        match_excludings = translate_excludings(excludings) + [:all_parts]
        match_excludings << :edition unless pubid.typed_stage&.abbr&.include?("DIR")
        # Only the candidate is built via .create (from the index) and so may
        # carry a compound part; `ref_pubid_no_year` is always a parsed pubid,
        # already split, so it needs no normalization.
        cand = normalize_compound_part(exclude_id_attrs(pubid, *match_excludings))
        cand == exclude_id_attrs(ref_pubid_no_year, *match_excludings)
      end

      # @TODO TEMP WORKAROUND (pubid 2.x migration): the v1-generated index
      # stores a compound part such as "5-1-3" in :part with no :subpart, and
      # Relaton::Index builds each row via Pubid::Iso::Identifier.from_hash(id),
      # which keeps it as part="5-1-3" subpart=nil. A parsed query splits it
      # (part="5", subpart="1-3"), so the two never compare equal. Re-split the
      # compound part on the first dash to mirror parse before comparing.
      # `exclude` returns a fresh instance, so mutating this copy is safe.
      # Remove once pubid create() splits compound parts itself.
      def normalize_compound_part(pubid)
        num = pubid.part&.value.to_s
        return pubid unless pubid.subpart.nil? && num.include?("-")

        head, tail = num.split("-", 2)
        pubid.part = ::Pubid::Iso::Components::Code.new(value: head)
        pubid.subpart = ::Pubid::Iso::Components::Code.new(value: tail)
        pubid
      end

      def exclude_id_attrs(pubid, *attrs)
        xid = pubid.exclude(*attrs)
        curr = xid
        while curr.base_identifier
          curr.base_identifier = curr.base_identifier.exclude(*attrs)
          curr = curr.base_identifier
        end
        xid
      end

      def excludings # rubocop:disable Metrics/AbcSize
        return @excludings if defined? @excludings

        excl_attrs = %i[year]
        excl_attrs << :part if ref.root.part.nil? || ref.root.all_parts
        if default_published_stage?(ref) || ref.root.all_parts
          excl_attrs << :stage
          excl_attrs << :iteration
        end
        @excludings = excl_attrs
      end

      # Pubid 2.x auto-populates a published-stage default on parse/.create,
      # so ref.stage is never nil. Treat that default as "no stage specified".
      def default_published_stage?(pubid)
        return true if pubid.typed_stage.nil?

        pubid.typed_stage.stage_code.to_s == "published"
      end

      def index
        @index ||= Relaton::Index.find_or_create(
          :iso,
          url: "#{ENDPOINT}#{INDEXFILE}.zip",
          file: "#{INDEXFILE}.yaml",
          pubid_class: ::Pubid::Iso::Identifier,
        )
      end

      def fetch_doc(options = {})
        @excludings = nil if options != opts
        @opts = options

        if !ref.root.all_parts || size == 1
          any? && first.item # (opts[:lang])
        else
          to_all_parts
        end
      end

      # @return [RelatonIsoBib::IsoBibliographicItem, nil]
      def to_all_parts # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity
        parts = @array.select { |h| h.pubid.part }
        if opts[:publication_date_before] || opts[:publication_date_after]
          parts = parts.select { |h| Bibliography.send(:year_in_range?, (h.pubid.date&.year || h.hit[:year]).to_i, opts) }
        end
        hit = parts.min_by { |h| h.pubid.part.value.to_i }
        return @array.first&.item unless hit

        bibitem = hit.item
        all_parts_item = bibitem.to_all_parts
        @array.reject { |h| h.pubid.part == hit.pubid.part }.each do |hi|
          all_parts_item.relation << create_relation(hi)
        end
        all_parts_item
      end

      def create_relation(hit)
        # pubid = Pubid.new hit.pubid
        docid = Docidentifier.new(content: hit.pubid, type: "ISO", primary: true)
        isobib = ItemData.new(formattedref: Bib::Formattedref.new(content: hit.pubid.to_s), docidentifier: [docid])
        Relation.new(type: "instanceOf", bibitem: isobib)
      end
    end
  end
end
