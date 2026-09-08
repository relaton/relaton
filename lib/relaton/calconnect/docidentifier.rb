module Relaton
  module Calconnect
    # A CalConnect document identifier that carries its parsed pubid alongside
    # the source string.
    #
    # Every published record carries exactly one docidentifier, `type:
    # CalConnect`, `primary: true`, in the form `CC[/<series>] <number>[:<date>]`
    # — `CC/DIR 10005:2019`, `CC 18011:2018`, `CC/WD 51017:2024-07-23`. That is
    # exactly what `Pubid::Calconnect::Identifier.parse` accepts, so nothing has
    # to synthesize or strip a publisher prefix.
    # `DataFetcher#index_id` takes `#pubid` straight from here to build the
    # `index-v2` rows.
    #
    # Follows the IHO/W3C shape rather than the ISO one: `content=` calls
    # `super` first, so `content` keeps the source string verbatim and
    # serialization is unchanged. That matters here beyond convention —
    # `Relaton::Calconnect::ItemData#create_id` derives the record's `id` from
    # `content.gsub(/\W+/, "")`, so a re-render would move every published id.
    #
    # Unlike W3C, CalConnect ids carry a date, so `remove_date!` is real and has
    # to re-render. It writes back through `store_content`, never `content=`: a
    # re-parse would rebuild `@pubid` from the string and discard the mutation.
    #
    # There is deliberately no `render` option to opt out of. `Pubid::Calconnect`
    # renders the publisher by default and models no edition or volume, so its
    # default output IS the stored docid form — the index key and the document's
    # own printed id are the same string. This is why the flavor needs no
    # `with_*` flag dance (contrast `Relaton::Ecma::Docidentifier`, which opts
    # out of two, and `Relaton::ThreeGpp::Docidentifier`, which opts in to one).
    class Docidentifier < Bib::Docidentifier
      attr_reader :pubid

      # Capture the inherited (LocalizedMarkedUpString) content setter before
      # overriding #content=, so #refresh_content! can write the re-rendered
      # string back WITHOUT re-parsing.
      alias_method :store_content, :content=

      def content=(value)
        super
        @pubid = value && parse(value)
      end

      # CalConnect's one optional component, and the only real mutator here.
      # `CC/DIR 10005:2019` -> `CC/DIR 10005`.
      def remove_date!
        return unless @pubid

        @pubid.date = nil
        refresh_content!
      end

      # No-ops, and not for lack of an override. A CalConnect number is one
      # token — `0812-1` and `0707.1` are numbers, not a number plus a part —
      # so `Pubid::Calconnect::Identifier` models no part, and there is nothing
      # for either of these to strip. Stated explicitly so the next reader does
      # not "fix" them by splitting the number.
      def remove_part!; end

      def to_all_parts!; end

      private

      # An identifier that does not parse is a data defect, so it is reported at
      # ERROR — never at WARN. It does not raise: an already-published record
      # still has to deserialize and render. The crawl escalates the same
      # failure into a tracked GitHub issue (see `DataFetcher#add_to_index` and
      # `Core::DataFetcher#report_errors`).
      def parse(value)
        ::Pubid::Calconnect::Identifier.parse value.to_s
      rescue StandardError => e
        Util.error "Failed to parse pubid `#{value}`: #{e.message}"
        nil
      end

      def refresh_content!
        store_content(@pubid.to_s)
      end
    end
  end
end
