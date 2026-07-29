module Relaton
  module Gost
    # Structured GOST document identifier. Wraps a Pubid::Gost identifier so the
    # canonical citation form (e.g. "GOST R 34.12-2015", "GOST 14946-82") stays
    # in sync with `content`, and undated-reference handling (return the latest
    # edition) can strip the year via the pubid. Mirrors Relaton::Oiml::Docidentifier.
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
        @pubid = ::Pubid::Gost.parse(value) if value
      rescue StandardError
        @pubid = nil
      end

      def remove_date!
        return unless @pubid

        # GOST pubid carries the edition as `year` (not `date`); nil-ing it and
        # re-rendering strips the year (e.g. `GOST R 34.12-2015` -> `GOST R 34.12`).
        # Re-sync `content` — mutating `@pubid` alone leaves the dated string.
        @pubid.year = nil
        self.content = @pubid.to_s
      end
    end
  end
end
