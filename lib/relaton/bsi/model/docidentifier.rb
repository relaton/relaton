require_relative "../../iso/type/pubid"

module Relaton
  module Bsi
    # BSI document identifier. Keeps the parsed `Pubid::Bsi::Identifier` as the
    # single stored value of `content` (via `Iso::Type::Pubid`, which preserves
    # the instance on the way in and stringifies it on the way out), so there is
    # one source of truth for the identifier — `#pubid` returns it and `#content`
    # renders it to a string. Non-BSI identifiers (e.g. ISBN) and anything pubid
    # can't parse are stored verbatim as plain strings.
    class Docidentifier < Bib::Docidentifier
      attribute :content, Iso::Type::Pubid

      def initialize(arg = nil, **kwargs)
        arg.is_a?(Hash) ? super(arg) : super(**kwargs)
        # Content may have been set before type during lutaml init. Re-run the
        # setter so the type-dependent parse (e.g. the ISBN bypass) applies.
        raw = arg.is_a?(Hash) ? (arg["content"] || arg[:content]) : kwargs[:content]
        self.content = raw if raw
      end

      alias_method :original_content=, :content=
      alias_method :original_content, :content

      # Store the parsed pubid instance (or the raw string for ISBN / anything
      # pubid can't parse) as the single source of truth.
      def content=(value)
        send(:original_content=, parse_pubid(value) || value)
      end

      # The rendered identifier — pubid instances are stringified.
      # @return [String, nil]
      def content
        original_content&.to_s
      end

      # The parsed identifier, when the content is a BSI reference. BSI has no
      # dedicated pubid `AllParts` subclass, so `#to_all_parts!` stores the
      # generic `Pubid::AllPartsIdentifier` wrapper here — not a
      # `Pubid::Bsi::Identifier` — hence the second branch.
      # @return [Pubid::Bsi::Identifier, Pubid::AllParts, nil]
      def pubid
        c = original_content
        c if c.is_a?(::Pubid::Bsi::Identifier) || c.is_a?(::Pubid::AllParts)
      end

      def to_s
        content.to_s
      end

      # Strip the publication date to build a most-recent (undated) reference.
      # pubid's `exclude` propagates into nested identifiers (so a consolidated
      # base date is dropped while the amendment is kept); `:month` is excluded
      # alongside `:date` because Flex stores the month separately.
      def remove_date!
        return unless pubid

        self.content = pubid.exclude(:date, :month)
      end

      # Strip the part (and subpart) to build a whole-standard reference.
      # pubid's `exclude` returns a new instance and propagates into nested
      # identifiers, so the part is dropped even on adopted (BS EN ISO …) and
      # consolidated (…+A1:…) ids while any amendment is kept.
      def remove_part!
        return unless pubid

        self.content = pubid.exclude(:part, :subpart)
      end

      # Reduce to the all-parts form by wrapping `pubid` (not a part-stripped
      # copy): `to_all_parts`'s own identity computation already strips
      # part/date for rendering (`#to_s`/`#===`), and wrapping the original
      # keeps `identifiers` holding the real identifier this reference came
      # from. The one exception is a supplement's own year: pubid protects an
      # `Amendment`/`Corrigendum`'s own date from a bare `exclude(:date)` (the
      # same protection `#remove_date!` above relies on to drop the base
      # year while keeping the amendment's), but `to_all_parts` builds its
      # identity through that same `exclude`, so the protection would leave a
      # consolidated id's amendment year distinguishing editions that
      # "(all parts)" is meant to collapse — hence the explicit
      # `exclude(:supplement_year)` pre-step, which force-clears it instead.
      # BSI has no dedicated pubid `AllParts` subclass (unlike ISO/IEC), so
      # the wrapper is the generic `Pubid::AllPartsIdentifier` — its `#to_s`
      # DOES print a "(all parts)" marker, unlike BSI's own renderer, which
      # never had one. Because BSI stores its parsed pubid as the single
      # source of `content` (`Iso::Type::Pubid`), `content` and `#pubid`
      # can't diverge here the way they do for flavors with a separately
      # cached content string: both now show the marker (see `#pubid` above,
      # widened to accept it).
      def to_all_parts!
        return if !pubid || pubid.all_parts?

        self.content = pubid.exclude(:supplement_year).to_all_parts
      end

      private

      # @return [Pubid::Bsi::Identifier, nil]
      def parse_pubid(value)
        case value
        when ::Pubid::Bsi::Identifier then value
        when String
          return nil if type == "ISBN"

          begin
            ::Pubid::Bsi::Identifier.parse(value)
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
