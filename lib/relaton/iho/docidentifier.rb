module Relaton
  module Iho
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
        # URN-typed docidentifiers carry the MRN form
        # (urn:mrn:iho:pub:spec:...), not a Pubid-parseable face — the
        # parse would raise on every bibdata read (metanorma-iho#573,
        # #603 emit these for S-4 update units and S-158:1xx primaries).
        # Detected from the value: type may not be assigned yet when the
        # setter fires during initialize.
        return if value.to_s.start_with?("urn:")

        @pubid = ::Pubid::Iho::Identifier.parse(value) if value
      end

      def remove_part!
        @pubid&.part = nil
      end

      def remove_date!
        @pubid&.date = nil
      end

      def to_all_parts!
        @pubid &&= @pubid.to_all_parts
      end
    end
  end
end
