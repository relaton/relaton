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
        attrs.map { |a| LEGACY_EXCLUDE_MAP[a] || a }
      end

      def ref_pubid_no_year
        @ref_pubid_no_year ||= ref.base_identifier ? ref.dup.tap { |r| r.base_identifier = r.base_identifier.exclude(:date) } : ref.exclude(:date)
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
        @array = index.search do |row|
          row[:id].is_a?(Hash) || row[:id].is_a?(::Pubid::Identifier) ? pubid_match?(row[:id]) : ref.to_s == row[:id]
        end.map { |row| Hit.new row, self }
          .sort_by! { |h| h.pubid.to_s }
          .reverse!
        self
      end

      def pubid_match?(id)
        pubid = create_pubid(id)
        return false unless pubid

        match_excludings = translate_excludings(excludings) + [:all_parts]
        match_excludings << :edition unless pubid.typed_stage&.abbr&.include?("DIR")
        exclude_id_attrs(pubid, *match_excludings) == exclude_id_attrs(ref_pubid_no_year, *match_excludings)
      end

      def create_pubid(id)
        return id if id.is_a?(::Pubid::Identifier)

        pubid = ::Pubid::Iso::Identifier.create(**id)
        if id[:stage] && pubid.typed_stage.nil?
          Util.warn "cannot parse typed stage or stage '#{id[:stage]}'", key: ref.to_s
          return nil
        end
        pubid
      rescue StandardError => e
        Util.warn e.message, key: ref.to_s
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
          id_keys: %i[publisher number copublisher part year edition type stage
                      iteration joint_document tctype sctype wgtype tcnumber
                      scnumber wgnumber dirtype base supplements addendum
                      jtc_dir month amendments corrigendums language],
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
