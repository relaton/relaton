module Relaton
  module Gb
    # A Chinese Standard identifier backed by `Pubid::Gb`.
    #
    # `content` stays a plain string, so serialization is unchanged; the parsed
    # identifier lives beside it in `@pubid` and drives the three mutators.
    # Follows the IALA, CEN and OMG shape (`lib/relaton/iala/docidentifier.rb`,
    # `lib/relaton/cen/model/docidentifier.rb`).
    class Docidentifier < Bib::Docidentifier
      # @return [Pubid::Gb::Identifier, nil] nil when the content is not a GB
      #   identifier, or the grammar cannot read it
      attr_reader :pubid

      # Capture the inherited (LocalizedMarkedUpString) content setter before
      # overriding #content=, so #replace_pubid writes the re-rendered string
      # back WITHOUT re-parsing it and discarding the mutation.
      alias_method :store_content, :content=

      def content=(value)
        super
        return unless value

        @pubid = begin
          # `pubid` is required lazily because deserialization reaches this
          # class without the flavor entry file having been loaded. LoadError
          # degrades to a plain string; StandardError covers a value that is
          # not a GB identifier. Both are DATA and must not raise. A malformed
          # *query* raises — see Bibliography.get.
          require "pubid"
          ::Pubid::Gb::Identifier.parse(value)
        rescue LoadError, StandardError
          nil
        end
      end

      def remove_part!
        return unless @pubid

        replace_pubid @pubid.exclude(:part)
      end

      def remove_date!
        return unless @pubid

        replace_pubid @pubid.exclude(:year)
      end

      # Strips the part and the date, then wraps the identifier in pubid's
      # `AllParts`. `Pubid::Gb::Identifiers::AllParts` renders the
      # ` (all parts)` marker itself and parses the form back, so — unlike CEN
      # and BSI, whose renderers have no marker — `content` is the wrapper's
      # own string (`GB/T 5606 (all parts)`, which
      # `spec/gb/fixtures/gbt_5606_2004_all_parts.xml` asserts).
      #
      # The guard keeps a second call from doubling the marker.
      def to_all_parts!
        return if !@pubid || @pubid.all_parts?

        replace_pubid @pubid.exclude(:part, :year).to_all_parts
      end

      private

      # `Pubid#exclude` returns a COPY, so the new identifier replaces the old
      # one.
      def replace_pubid(new_pubid)
        @pubid = new_pubid
        store_content @pubid.to_s
      end
    end
  end
end
