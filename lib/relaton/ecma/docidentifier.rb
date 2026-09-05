module Relaton
  module Ecma
    # Structured ECMA document identifier. The docid string is the BARE printed
    # form ("ECMA-269", "ECMA TR/101", "ECMA MEM/2021"), and it is parsed into a
    # `Pubid::Ecma::Identifier` kept in `@pubid` while the lutaml `content`
    # attribute stays a plain string for serialization.
    #
    # Parsing is **soft**: `content=` lazily requires pubid and rescues
    # `LoadError`/`StandardError`, so a missing pubid gem or non-ECMA content
    # leaves `@pubid` nil rather than raising.
    #
    # ## Why this class exists, and the one rule that is ECMA-specific
    #
    # `Pubid::Ecma::Identifier#to_s` renders the edition and the volume **by
    # default** — `"ECMA-269 ed3 vol2"`. That default is deliberate on the pubid
    # side: `Relaton::Index::Type#add_or_update` keys on a bare `id.to_s`, and
    # 740 of the 804 published rows carry an edition, so without it 383 rows
    # collapse onto another row's key and vanish from the index.
    #
    # A **document's own** docidentifier is the opposite. Every `ECMA-269`
    # volume file in `relaton-data-ecma` carries `docidentifier: ECMA-269` and
    # the same title — the edition and the volume are index metadata, not part
    # of the printed id. So `refresh_content!` must opt OUT of both, or a
    # mutation would silently promote the stored content to the index form.
    #
    # This is the mirror image of `Relaton::ThreeGpp::Docidentifier`, whose
    # `refresh_content!` must pass `with_publisher: true` because ITS pubid
    # defaults to the index rendering and its stored content is the fuller one.
    # The two look contradictory only until you notice each one re-renders what
    # its own stored `content` already holds.
    class Docidentifier < Bib::Docidentifier
      attr_reader :pubid

      # Capture the inherited (LocalizedMarkedUpString) content setter before
      # overriding #content=, so #refresh_content! can write the re-rendered
      # string back WITHOUT re-parsing (a re-parse would rebuild @pubid from the
      # string and discard in-place mutations).
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
          require "pubid"
          ::Pubid::Ecma::Identifier.parse(value.to_s)
        rescue LoadError, StandardError
          nil
        end
      end

      # `Pubid::Ecma::Identifier` models number/part/subpart/edition/volume, so
      # the mapping is:
      #
      # - **`remove_date!` → clears `edition`.** ECMA has no date component;
      #   `edition` is its version discriminator, so clearing it yields the
      #   version-agnostic ("most recent") reference. It is invisible in the
      #   rendered bare form, which never carried the edition to begin with —
      #   but the identifier really does change, and a consumer reading
      #   `#pubid` sees it.
      # - **`remove_part!` → clears `part`/`subpart`.** Real here:
      #   "ECMA-418-1" -> "ECMA-418".
      # - **`to_all_parts!` → both, plus `all_parts`** behind a `respond_to?`
      #   guard; the ECMA renderer emits no marker for the flag, so the
      #   stripped id is the best available rendering.
      #
      # All three no-op safely when `@pubid` is nil, so `Bib::ItemData`'s
      # `#to_all_parts` / `#to_most_recent_reference` never raise on ECMA items.

      def remove_part!
        clear_attrs! :part
      end

      def remove_date!
        clear_attrs! :edition
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

        cleared.each { |attr| @pubid.public_send("#{attr}=", nil) }
        @pubid.subpart = nil if attrs.include?(:part) && @pubid.respond_to?(:subpart=)
        refresh_content!
      end

      def refresh_content!
        store_content(render(@pubid)) if @pubid
      end

      # The bare document form. See the class comment for why both flags are
      # opted out of, and why 3GPP's twin does the opposite.
      def render(pubid)
        pubid.to_s(with_edition: false, with_volume: false)
      end
    end
  end
end
