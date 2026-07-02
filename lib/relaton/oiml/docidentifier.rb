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
