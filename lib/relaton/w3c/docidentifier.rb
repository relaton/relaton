module Relaton
  module W3c
    # A W3C document identifier that carries its parsed pubid alongside the
    # source string.
    #
    # `DataParser#pub_id` builds `"W3C REC-xml-names-20091208"` — publisher
    # prefix included — which is exactly the form
    # `Pubid::W3c::Identifier.parse` accepts, so nothing has to synthesize or
    # strip a prefix. `DataFetcher#index_primary` takes `#pubid` straight from
    # here to build the `index-v2` rows.
    #
    # Follows the IHO shape rather than the ISO one: `content=` calls `super`
    # first, so `content` keeps the source string verbatim and serialization is
    # unchanged. ISO re-renders `content` from the pubid, which W3C has no need
    # of and which would alter its published output.
    class Docidentifier < Bib::Docidentifier
      attr_reader :pubid

      def content=(value)
        super
        @pubid = value && parse(value)
      end

      # W3C identifiers carry no part, date-as-component or all-parts notion, so
      # the three mutators `Bib::ItemData` broadcasts over every docidentifier
      # are no-ops here rather than the inherited NotImplementedError.
      def remove_part!; end

      def remove_date!; end

      def to_all_parts!; end

      private

      # An identifier that does not parse is a data defect, so it is reported at
      # ERROR — never at WARN. It does not raise: an already-published record
      # still has to deserialize and render. The crawl escalates the same
      # failure into a tracked GitHub issue (see
      # `DataFetcher#index_primary` and `Core::DataFetcher#report_errors`).
      def parse(value)
        ::Pubid::W3c::Identifier.parse value.to_s
      rescue StandardError => e
        Util.error "Failed to parse pubid `#{value}`: #{e.message}"
        nil
      end
    end
  end
end
