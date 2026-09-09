module Relaton
  module Oasis
    # Structured OASIS document identifier. The docid string is the printed
    # form, which carries the "OASIS " publisher token
    # (e.g. "OASIS OSLC-CoreShapes-3.0-PS01-Pt8"), and it is parsed into a
    # `Pubid::Oasis::Identifier` kept in `@pubid` while the lutaml `content`
    # attribute stays a plain string for serialization.
    #
    # Parsing is **soft**: `content=` lazily requires pubid and rescues
    # `LoadError`/`StandardError`, so a missing pubid gem or non-OASIS content
    # leaves `@pubid` nil rather than raising. A reference without the publisher
    # token ("amqp-core") is not an OASIS printed id, so it leaves `@pubid` nil
    # too; `DataFetcher` always builds the token-carrying form.
    #
    # ## Why the three mutators stay no-ops
    #
    # `Pubid::Oasis::Renderer` echoes the verbatim slug held in `original`, so
    # clearing `part`, `version` or `stage` cannot change the printed id — the
    # mutation would be invisible, and rewriting `original` would invent a
    # reference form OASIS does not publish. OASIS slugs are free-form with an
    # inconsistent internal structure, and no OASIS citation drops a part or a
    # version; there is no "all parts" or "most recent" spelling to render.
    #
    # So this class deliberately does NOT override `remove_part!`,
    # `remove_date!` or `to_all_parts!`. Since `dfbd26c72` the `Bib::Docidentifier`
    # defaults are no-ops rather than `NotImplementedError` raises, so
    # `Bib::ItemData#to_all_parts` and `#to_most_recent_reference` return the
    # item unchanged instead of blowing up. That is the honest OASIS answer.
    # (Contrast `Relaton::Ogc::Docidentifier`, whose components really do
    # render, so its mutators re-render the content.)
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
          require "pubid"
          ::Pubid::Oasis::Identifier.parse(value.to_s)
        rescue LoadError, StandardError
          nil
        end
      end
    end
  end
end
