module Relaton
  module Cen
    # A CEN/CENELEC document identifier backed by `Pubid::CenCenelec`.
    #
    # `content` stays a plain string, so serialization is unchanged; the parsed
    # identifier lives beside it in `@pubid` and drives the three mutators.
    # Follows the IALA shape (`lib/relaton/iala/docidentifier.rb`), which
    # `lib/relaton/bib/model/docidentifier.rb` names as the reference. CEN has
    # no relaton-iso dependency, so BSI's `Iso::Type::Pubid` lutaml type does
    # not fit here.
    class Docidentifier < Bib::Docidentifier
      # @return [Pubid::CenCenelec::Identifier, nil] nil when the content is
      #   not a CEN identifier, or the grammar cannot read it
      attr_reader :pubid

      # Capture the inherited (LocalizedMarkedUpString) content setter before
      # overriding #content=, so #refresh_content! writes the re-rendered string
      # back WITHOUT re-parsing it and discarding the mutation.
      alias_method :store_content, :content=

      def content=(value)
        super
        return unless value

        @pubid = begin
          # `pubid` is required lazily because deserialization reaches this
          # class without the flavor entry file having been loaded. LoadError
          # degrades to a plain string; StandardError covers a non-CEN value
          # (an ISBN) and a code the grammar rejects (`prEN 13306 rev`), both
          # of which are DATA and must not raise. A malformed *query* raises —
          # see Bibliography.parse.
          require "pubid"
          ::Pubid::CenCenelec::Identifier.parse(value)
        rescue LoadError, StandardError
          nil
        end
      end

      # Drops the LAST year, and only that one.
      #
      # On a supplement the identifier names the supplement, so its own year is
      # the last one: `EN 13250:2000/A1:2005` is amendment A1 of 2005, and the
      # `2000` belongs to the base document it amends. Excluding that base year
      # would strip the base document's identity rather than a date. Where there
      # is no supplement year the document's own year is the base year.
      #
      # This also closes a case the old `/:\d{4}$/` regex missed:
      # `EN 61375-2-3:2015/AC:2016-11` does not end in a bare year, so the regex
      # stripped nothing, while `exclude(:supplement_year)` resets the
      # supplement's year and month together.
      def remove_date!
        return unless @pubid

        stripped = @pubid.exclude(:supplement_year)
        stripped = @pubid.exclude(:year) if stripped == @pubid
        replace_pubid stripped
      end

      def remove_part!
        return unless @pubid

        replace_pubid @pubid.exclude(:part, :subpart)
      end

      # Strips the part and the date, and flags the identifier.
      #
      # `Pubid::CenCenelec::Renderer` never reads `all_parts`, so the flag is
      # invisible in `content` — measured on pubid `b4d52e5d6`, setting it on
      # `EN 1325` renders `EN 1325` either way. So this degrades to a rendered
      # part-and-date strip while the flag is set structurally, for anything
      # that later reads the pubid rather than the string. Same trade-off as
      # `Relaton::Bsi::Docidentifier` and `Relaton::Iala::Docidentifier`, whose
      # renderers emit no all-parts marker either.
      def to_all_parts!
        return unless @pubid

        remove_part!
        remove_date!
        @pubid.all_parts = true
        refresh_content!
      end

      private

      # `Pubid#exclude` returns a COPY (the BSI shape), so the new identifier
      # replaces the old one; it does not mutate in place as IALA's setters do.
      def replace_pubid(new_pubid)
        @pubid = new_pubid
        refresh_content!
      end

      def refresh_content!
        store_content(@pubid.to_s) if @pubid
      end
    end
  end
end
