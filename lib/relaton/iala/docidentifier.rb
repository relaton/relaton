module Relaton
  module Iala
    # Structured IALA document identifier. The docid string is the canonical
    # form (e.g. "IALA S1070 Ed 2.0"). Defined as a subclass so future
    # Pubid::Iala integration can hook in via #pubid without changing the
    # public interface.
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
        return unless value

        @pubid = begin
          require "pubid/iala"
          ::Pubid::Iala.parse(value)
        rescue LoadError, StandardError
          nil
        end
      end
    end
  end
end
