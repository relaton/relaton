# frozen_string_literal: true

module Relaton
  module Jis
    # A JIS document identifier, backed by `Pubid::Jis`.
    #
    # `content` stays the source string for serialization. `#pubid` parses it
    # into a `Pubid::Jis::Identifier`, and the three mutators change that pubid
    # and render it back into `content`. There is no string surgery.
    #
    # The parse is lazy and soft, as in `Relaton::Itu::Docidentifier`: it runs
    # on first use, and content that does not parse gives a nil `#pubid`, with
    # no log. The all-parts form "JIS C 0364 (all parts)" does not parse, and
    # a cached all-parts item is deserialized again, so a log would be noise.
    # With a nil `#pubid` the mutators do nothing.
    #
    # ## Rendering rules
    #
    # - The `JIS ` publisher is rendered only when the source has it. pubid
    #   always adds it, but the source spells a technical report
    #   `TR Z 0010:2008`.
    # - Everything else is the pubid canonical spelling. pubid does not keep the
    #   source spelling `AMENDMENT 1` / `EXPLANATION 1`, so a changed supplement
    #   renders as `AMD 1` / `EXPL 1`, the form that the index uses.
    # - The all-parts marker is ` (all parts)`, as in
    #   `Relaton::Jis::StructuredIdentifier`, not the pubid `（規格群）`.
    #   `Bibliography.get` accepts both as a reference.
    class Docidentifier < Bib::Docidentifier
      # Capture the inherited content setter before the override, so that a
      # mutation can write the rendered string back and keep the changed pubid.
      # `content=` would clear it, and a new parse of "… (all parts)" fails.
      alias_method :store_content, :content=

      def content=(value)
        super
        @pubid = nil
        @pubid_parsed = false
      end

      # @return [Pubid::Jis::Identifier, nil] nil if the content does not parse
      def pubid
        return @pubid if @pubid_parsed

        @pubid_parsed = true
        @pubid = parse
      end

      # Removes every part level: `JIS C 0364-2-21:1999` -> `JIS C 0364:1999`.
      # For a supplement, the part is on its base.
      def remove_part!
        return unless pubid

        change_document { |id| id.exclude(:parts) }
        refresh_content!
      end

      # Removes the year and the reaffirmation marker:
      # `JIS C 9901:2019R` -> `JIS C 9901`.
      #
      # For a supplement, only the base loses its date, and the supplement keeps
      # its own year: `JIS B 3700-101:1996/CORRIGENDUM 1:2002` ->
      # `JIS B 3700-101/CORRIGENDUM 1:2002`. pubid renders a supplement without
      # a year as `…/CORRIGENDUM 1:`, with a trailing colon.
      def remove_date!
        return unless pubid

        change_document { |id| id.exclude(:year, :reaffirmed) }
        refresh_content!
      end

      # `JIS C 0364-2-21:1999` -> `JIS C 0364 (all parts)`, with `all_parts`
      # set on `#pubid`.
      def to_all_parts!
        return unless pubid

        change_document { |id| id.exclude(:parts, :year, :reaffirmed) }
        @pubid.all_parts = true
        store_content "#{render(@pubid.exclude(:all_parts))} (all parts)"
      end

      private

      def parse
        return unless content

        require "pubid"
        ::Pubid::Jis::Identifier.parse content.to_s
      rescue LoadError, StandardError
        nil
      end

      # Applies the change to the document identifier: the pubid itself, or the
      # base of a supplement. Copy on write, as `Pubid::Identifier#exclude` is:
      # an argument-less `exclude` copies the supplement, so a pubid that a
      # caller got before the mutation does not change.
      def change_document(&)
        @pubid = document_changed(@pubid, &)
      end

      def document_changed(id, &)
        return yield(id) unless id.is_a?(::Pubid::Jis::SupplementIdentifier)

        id.exclude.tap { |copy| copy.base &&= document_changed(copy.base, &) }
      end

      def refresh_content!
        store_content render(@pubid)
      end

      def render(id)
        id.to_s(with_publisher: content.to_s.start_with?("JIS"))
      end
    end
  end
end
