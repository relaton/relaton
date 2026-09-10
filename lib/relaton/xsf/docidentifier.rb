module Relaton
  module Xsf
    # An XSF document identifier, backed by `Pubid::Xsf`.
    #
    # Parses its `content` into a `Pubid::Xsf::Identifier` kept in `@pubid`,
    # while the lutaml `content` attribute stays a plain **string** for
    # serialization. Parsing is **soft**: `content=` lazily requires pubid and
    # rescues `LoadError`/`StandardError`, so a missing gem or non-XSF content
    # leaves `@pubid` nil rather than raising during deserialization.
    #
    # **It deliberately implements none of `remove_part!` / `remove_date!` /
    # `to_all_parts!`.** An XEP identifier is a publisher and a number and
    # nothing else — no part, no edition, no date — so there is genuinely
    # nothing for any of them to strip, and `Bib::Docidentifier` already
    # defaults all three to no-ops for exactly that case. Empty overrides here
    # would assert a flavor-specific rule that does not exist. Compare
    # `Relaton::Ogc::Docidentifier`, which overrides `remove_date!` because OGC
    # really does carry a revision.
    #
    # So this class exists for `#pubid`: it gives consumers the structured
    # identifier off a docidentifier, the way every other pubid-backed flavor
    # does, without changing what is serialized.
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
          ::Pubid::Xsf::Identifier.parse(value)
        rescue LoadError, StandardError
          nil
        end
      end
    end
  end
end
