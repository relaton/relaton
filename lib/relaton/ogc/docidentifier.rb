module Relaton
  module Ogc
    # Structured OGC document identifier. The docid string is the canonical
    # printed form, which carries no publisher token (e.g. "19-025r1"), and it
    # is parsed into a `Pubid::Ogc::Identifier` kept in `@pubid` while the
    # lutaml `content` attribute stays a plain string for serialization.
    #
    # Parsing is **soft**: `content=` lazily requires pubid and rescues
    # `LoadError`/`StandardError`, so a missing pubid gem or non-OGC content
    # leaves `@pubid` nil rather than raising.
    #
    # Before this class had a body it inherited `Bib::Docidentifier`, whose
    # `remove_part!` / `remove_date!` / `to_all_parts!` each raise
    # `NotImplementedError` — and `Bib::ItemData` broadcasts all three to every
    # docidentifier, so `#to_all_parts` and `#to_most_recent_reference` raised
    # on **every** OGC item. `NotImplementedError` descends from `ScriptError`,
    # so a caller's `rescue => e` did not even catch it.
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
          require "pubid"
          ::Pubid::Ogc::Identifier.parse(value)
        rescue LoadError, StandardError
          nil
        end
      end

      # `Pubid::Ogc::Identifier` models only `year`/`number`/`revision`, so the
      # mapping is OGC-specific:
      #
      # - **`remove_date!` → clears `revision`.** OGC carries no date component;
      #   `revision` is its version discriminator — the same component a
      #   reference may omit, which `HitCollection#best_match` then treats as a
      #   wildcard — so clearing it yields
      #   the version-agnostic ("most recent") reference: `12-128r19` →
      #   `12-128`.
      # - **`year` is never cleared.** It looks date-like but is half the
      #   document number (`12-128`), not a publication qualifier; dropping it
      #   would leave `-128`, which identifies nothing.
      # - **`remove_part!` → clears the (unused) `part`/`subpart` attributes.**
      #   A no-op for the rendered string today: OGC has no part component.
      #   Implemented anyway so it never raises, and it starts working
      #   automatically if pubid-ogc ever models one. (The IALA precedent.)
      # - **`to_all_parts!` → both, then wraps `@pubid` in pubid's `AllParts`.**
      #   `content` stays the plain stripped id — OGC's own renderer has no
      #   "(all parts)" marker, and `content` is cached from the pre-wrap
      #   pubid on purpose. `#pubid` itself, read directly, now answers
      #   `all_parts? == true` and renders WITH pubid's generic marker
      #   (`#to_s`), since it's the wrapper.
      #
      # All three no-op safely when `@pubid` is nil, so `Bib::ItemData`'s
      # `#to_all_parts` / `#to_most_recent_reference` never raise on OGC items.
      #
      # `refresh_content!` renders a bare `to_s`: the OGC printed form has no
      # publisher token and the stored `content` does not carry one either, so
      # unlike 3GPP this must NOT pass `with_publisher: true`.

      def remove_part!
        clear_attr!(:part)
      end

      def remove_date!
        clear_attr!(:revision)
      end

      def to_all_parts!
        return if !@pubid || @pubid.all_parts?

        # `#exclude` (no args) rebuilds a full independent copy — `remove_part!`
        # / `remove_date!` mutate `@pubid` in place, so a bare reference here
        # would lose the original revision to that mutation too.
        original = @pubid.exclude
        remove_part!
        remove_date!
        @pubid = original.to_all_parts
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
