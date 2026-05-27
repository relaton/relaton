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
        @pubid = ::Pubid::Iho::Identifier.parse(value) if value
      end

      def to_h
        return super unless @pubid

        # Mirrors Bibliography.pubid_attrs but keyed for downstream consumers
        # that expect the legacy pubid 1.x shape (:number for IHO's :code).
        {
          publisher: "IHO",
          type: @pubid.class.type[:short],
          number: @pubid.code,
          version: @pubid.version,
          part: @pubid.part,
          appendix: (@pubid.appendix if @pubid.respond_to?(:appendix)),
          annex: (@pubid.annex if @pubid.respond_to?(:annex)),
          supplement: (@pubid.supplement if @pubid.respond_to?(:supplement)),
        }.compact
      end

      def remove_part!
        @pubid&.part = nil
      end

      def remove_date!
        @pubid&.date = nil
      end

      def to_all_parts!
        @pubid&.all_parts = true
      end
    end
  end
end
