module Relaton
  module Wmo
    # Structured WMO document identifier. The docid string is the canonical
    # form (e.g. "WMO-No. 8", "WMO/TD-No. 1551", "JCOMM Technical Report
    # No. 5", "GAW Report No. 234"); its `content` is soft-parsed into a
    # Pubid::Wmo identifier kept in `@pubid`, mirroring
    # Relaton::Adobe::Docidentifier.
    #
    # Parsing is soft: a non-WMO string (e.g. a page title) leaves `@pubid`
    # nil rather than raising, so the plain `content` string still
    # round-trips.
    class Docidentifier < Bib::Docidentifier
      attr_reader :pubid

      def initialize(attrs = {}, options = {})
        pubid = attrs.is_a?(Hash) ? attrs.delete(:pubid) : nil
        attrs[:content] ||= pubid.to_s if pubid
        super
        @pubid = pubid if pubid
      end

      def content=(value)
        super
        @pubid = ::Pubid::Wmo.parse(value) if value
      rescue StandardError
        @pubid = nil
      end

      # WMO identifiers carry no part/date/all-parts component (edition
      # and volume live on the record, not the id), so the base class's
      # abstract mutation hooks are safe no-ops: they keep
      # `Bib::ItemData#to_most_recent_reference` / `#to_all_parts` from
      # raising on WMO items, and never change the rendered `content`.
      def remove_part!; end

      def remove_date!; end

      def to_all_parts!; end
    end
  end
end
