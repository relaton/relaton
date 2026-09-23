module Relaton
  module Oiml
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
        @pubid = ::Pubid::Oiml.parse(value) if value
      rescue StandardError
        @pubid = nil
      end

      # Both mutators go through #exclude (an immutable copy) rather than
      # mutating `@pubid` in place: for a plain identifier the two are
      # equivalent, but for a Pubid::Oiml::Identifiers::DualPublished
      # (pubid#437, e.g. `ISO 4064-1:2024|OIML R 49-1:2024`) a direct
      # `@pubid.part = nil`/`@pubid.date = nil` is a silent no-op — neither
      # attribute is delegated to either side — while `#exclude` correctly
      # recurses into both sides. `content=` re-parses the rendered string,
      # which resyncs `@pubid` too, so there is nothing left to reassign here.
      def remove_part!
        return unless @pubid

        self.content = @pubid.exclude(:part).to_s
      end

      def remove_date!
        return unless @pubid

        # Re-sync `content` from the now-dateless pubid: it is the string that
        # actually renders (e.g. `OIML R 138`, or `OIML R 138 (E)` keeping the
        # language). Mutating `@pubid` alone leaves the dated `content` in place.
        self.content = @pubid.exclude(:date).to_s
      end

      def to_all_parts!
        @pubid &&= @pubid.to_all_parts
      end
    end
  end
end
