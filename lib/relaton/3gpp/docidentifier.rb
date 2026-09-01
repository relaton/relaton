module Relaton
  module ThreeGpp
    # Structured 3GPP document identifier. `content` stays the canonical string
    # (e.g. "3GPP TS 29.198-04-1:REL-5/5.0.0") and the parsed
    # `Pubid::Tgpp::Identifier` is kept alongside it in `@pubid`.
    #
    # Without this subclass 3GPP items inherit `Bib::Docidentifier`, whose
    # `remove_part!` / `remove_date!` / `to_all_parts!` all raise
    # NotImplementedError — so `ItemData#to_all_parts` and
    # `#to_most_recent_reference`, which broadcast to every docidentifier,
    # raised on every 3GPP item.
    class Docidentifier < Bib::Docidentifier
      attr_reader :pubid

      # Capture the inherited (LocalizedMarkedUpString) content setter before
      # overriding #content=, so #refresh_content! can write the re-rendered
      # string back WITHOUT re-parsing (a re-parse would rebuild @pubid from
      # the string and discard the in-place mutations just made).
      alias_method :store_content, :content=

      def initialize(attrs = {}, options = {})
        pubid = attrs.is_a?(Hash) ? attrs.delete(:pubid) : nil
        attrs[:content] ||= render(pubid) if pubid
        super
        @pubid = pubid if pubid
      end

      def content=(value)
        super
        return unless value

        @pubid = begin
          # Rescue LoadError so a missing pubid gem degrades to a plain string,
          # and StandardError so non-3GPP or unparseable content just leaves
          # @pubid nil rather than raising. Deserialization reaches this setter
          # without the flavor entry file necessarily having been loaded, hence
          # the local require.
          require "pubid"
          ::Pubid::Tgpp::Identifier.parse(value.to_s)
        rescue LoadError, StandardError
          nil
        end
      end

      # `Pubid::Tgpp::Identifier` models number/suffix/parts/release/version.
      # It has no date, and `suffix` is folded into the document code, so:
      #
      #   * #remove_part! clears `parts` — a real, separable component here
      #     (unlike IALA's, which is a no-op): "TS 29.198-04-1" -> "TS 29.198".
      #   * #remove_date! clears `release` AND `version`. 3GPP carries no date;
      #     those two are its version discriminators — the same pair
      #     `Bibliography#ignored` treats as omittable — so clearing both gives
      #     the version-agnostic ("most recent") reference "TS 23.207".
      #   * #to_all_parts! does both, and sets `all_parts`. That attribute is
      #     inherited from the pubid base class, but the Tgpp renderer emits no
      #     marker for it, so the flag is invisible in the rendered string —
      #     the parts-and-version-stripped id is the best available rendering.
      #     Guarded by `respond_to?` anyway, as IALA does.
      #
      # All three no-op safely when @pubid is nil (parse failed, or the pubid
      # gem is unavailable), so ItemData#to_all_parts and
      # #to_most_recent_reference never raise on 3GPP items.

      def remove_part!
        clear_attrs! :parts
      end

      def remove_date!
        clear_attrs! :release, :version
      end

      def to_all_parts!
        return unless @pubid

        remove_part!
        remove_date!
        @pubid.all_parts = true if @pubid.respond_to?(:all_parts=)
        refresh_content!
      end

      private

      def clear_attrs!(*attrs)
        return unless @pubid

        cleared = attrs.select { |attr| @pubid.respond_to?("#{attr}=") }
        return if cleared.empty?

        # `parts` is a collection: empty it rather than nil it, so #code keeps
        # rendering through `parts.map` instead of tripping over nil.
        cleared.each do |attr|
          @pubid.public_send("#{attr}=", attr == :parts ? [] : nil)
        end
        refresh_content!
      end

      def refresh_content!
        store_content(render(@pubid)) if @pubid
      end

      # `Pubid::Tgpp::Identifier#to_s` defaults to OMITTING the "3GPP " token —
      # deliberately, so it reproduces the index id. The stored docidentifier
      # content carries the prefix ("3GPP TS 23.207:REL-4/4.0.0"), so every
      # render here must opt back in or a mutation would silently strip it.
      def render(pubid)
        pubid.to_s(with_publisher: true)
      end
    end
  end
end
