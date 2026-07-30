module Relaton
  module Adobe
    # Structured Adobe document identifier. The docid string is the canonical
    # form (e.g. "Adobe TN 5014", "Adobe Publication adobe-glyph-list"); its
    # `content` is soft-parsed into a Pubid::Adobe identifier kept in `@pubid`
    # (a TechNote or Publication), mirroring Relaton::Oiml::Docidentifier.
    #
    # Parsing is soft: a non-Adobe or non-canonical string (e.g. a title-cased
    # "Adobe Glyph List") leaves `@pubid` nil rather than raising, so the plain
    # `content` string still round-trips.
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
        @pubid = ::Pubid::Adobe.parse(value) if value
      rescue StandardError
        @pubid = nil
      end

      # Adobe identifiers carry no part/date/all-parts component, so the base
      # class's abstract mutation hooks (which otherwise raise NotImplementedError)
      # are implemented as safe no-ops over the wrapped pubid: they keep
      # `Bib::ItemData#to_most_recent_reference` / `#to_all_parts` from raising on
      # Adobe items, and never change the rendered `content`.
      def remove_part!
        @pubid&.part = nil
      end

      def remove_date!
        return unless @pubid

        @pubid.date = nil
        self.content = @pubid.to_s
      end

      def to_all_parts!
        @pubid&.all_parts = true
      end
    end
  end
end
