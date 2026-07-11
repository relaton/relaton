module Relaton
  module Iala
    # Structured IALA document identifier. The docid string is the canonical
    # form (e.g. "IALA S1070 Ed 2.0"). Defined as a subclass so future
    # Pubid::Iala integration can hook in via #pubid without changing the
    # public interface.
    class Docidentifier < Bib::Docidentifier
      attr_reader :pubid

      # Capture the inherited (LocalizedMarkedUpString) content setter before
      # overriding #content=, so #refresh_content! can write the re-rendered
      # string back WITHOUT re-parsing (a re-parse would rebuild @pubid from the
      # string and discard in-place mutations such as `all_parts = true`).
      alias_method :store_content, :content=

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
          # `pubid/iala` needs pubid core (Pubid::PrefixesSupport) loaded first,
          # so require both. Rescue LoadError so a missing pubid gem degrades to
          # a plain string, and StandardError so non-IALA/unparseable content
          # just leaves @pubid nil rather than raising.
          require "pubid"
          require "pubid/iala"
          ::Pubid::Iala.parse(value)
        rescue LoadError, StandardError
          nil
        end
      end

      # IALA's Pubid::Iala::Identifier models only publisher/number/edition/
      # language. It has no distinct `date` component and folds any subpart
      # inline into `number` (e.g. "0103-1"), so:
      #   * #remove_date! maps onto `edition` — IALA's version discriminator —
      #     yielding the version-agnostic ("most recent") reference.
      #   * #remove_part! clears the (currently-unused) part/subpart attributes;
      #     it is a no-op for the rendered content today, but is implemented so
      #     it never raises and starts working automatically should pubid-iala
      #     ever model `part` separately.
      # All three no-op safely when @pubid is nil (parse failed or the pubid gem
      # is unavailable), so Bib::ItemData#to_all_parts / #to_most_recent_reference
      # never raise on IALA items.

      def remove_part!
        clear_attr!(:part)
      end

      def remove_date!
        clear_attr!(:edition)
      end

      def to_all_parts!
        return unless @pubid

        remove_part!
        remove_date!
        @pubid.all_parts = true if @pubid.respond_to?(:all_parts=)
        refresh_content!
      end

      private

      def clear_attr!(attr)
        return unless @pubid && @pubid.respond_to?("#{attr}=")

        @pubid.public_send("#{attr}=", nil)
        @pubid.subpart = nil if attr == :part && @pubid.respond_to?(:subpart=)
        refresh_content!
      end

      def refresh_content!
        store_content(@pubid.to_s) if @pubid
      end
    end
  end
end
