module Relaton
  module Evs
    # An EVS document identifier backed by `Pubid::Evs`.
    #
    # `content` stays a plain string, so serialization is unchanged; the parsed
    # identifier lives beside it in `@pubid` and drives the three mutators.
    # Follows `Relaton::Cen::Docidentifier`. The parse is on the DATA side: it
    # lazily requires pubid and rescues `LoadError`/`StandardError`, so a
    # non-EVS value or a code the grammar rejects stays verbatim with `@pubid`
    # nil, and all three mutators no-op. A malformed *query* raises — see
    # `Bibliography.parse`.
    class Docidentifier < Bib::Docidentifier
      # @return [Pubid::Evs::Identifier, nil]
      attr_reader :pubid

      # Capture the inherited (LocalizedMarkedUpString) content setter before
      # overriding #content=, so #refresh_content! writes the re-rendered string
      # back WITHOUT re-parsing it and discarding the mutation.
      alias_method :store_content, :content=

      def content=(value)
        super
        return unless value

        @pubid = begin
          require "pubid"
          ::Pubid::Evs.parse(value)
        rescue LoadError, StandardError
          nil
        end
      end

      # Drops the LAST year, and only that one. On a supplement the identifier
      # names the supplement (`EVS-EN ISO 9001:2015/A1:2024` is amendment A1 of
      # 2024), so the supplement year goes first and the base document's year
      # only when there is no supplement year.
      def remove_date!
        return unless @pubid

        stripped = @pubid.exclude(:supplement_year)
        stripped = @pubid.exclude(:year) if stripped == @pubid
        replace_pubid stripped
      end

      def remove_part!
        return unless @pubid

        replace_pubid @pubid.exclude(:part)
      end

      # Strips the part and the date, then wraps `@pubid` in pubid's `AllParts`
      # wrapper. `content` stays the plain part-and-date-stripped string on
      # purpose (same trade-off as `Relaton::Cen::Docidentifier`); `#pubid`
      # read directly answers `all_parts? == true` and renders WITH pubid's
      # own "(all parts)" marker.
      def to_all_parts!
        return if !@pubid || @pubid.all_parts?

        original = @pubid.exclude
        remove_part!
        remove_date!
        @pubid = original.to_all_parts
      end

      private

      # `Pubid#exclude` returns a COPY (the BSI/CEN shape), so the new
      # identifier replaces the old one; it does not mutate in place.
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
