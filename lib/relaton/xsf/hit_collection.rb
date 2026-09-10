module Relaton
  module Xsf
    class HitCollection < Relaton::Core::HitCollection
      GHDATA_URL = "https://raw.githubusercontent.com/relaton/relaton-data-xsf/v2/".freeze

      #
      # Find the index rows for the identifier this collection was built with.
      #
      # `ref` is a `Pubid::Xsf::Identifier` -- `Bibliography.parse_ref` does that
      # step, and raises rather than returning nil for an unrecognized
      # reference. Passing the identifier rather than a string is what enables
      # the binary search on `id.root.number`. The nil guard in `#rows` is
      # defensive only: `Core::HitCollection` permits a nil `ref`, and an empty
      # result beats a NoMethodError if some other caller constructs one.
      #
      # An XEP identifier is only a publisher and a number: no edition, no date,
      # no part. So nothing is ignorable and `matches?` is a plain equality --
      # which is the point. Ids are unique, one row per XEP, so there is no
      # selection order to apply either.
      #
      # @return [self]
      #
      def search
        @array = rows.map { |row| Hit.new url: "#{GHDATA_URL}#{row[:file]}" }
        self
      rescue Relaton::RequestError
        raise
      rescue StandardError => e
        raise Relaton::RequestError, e.message
      end

      def index
        @index ||= Relaton::Index.find_or_create(
          :xsf,
          url: "#{GHDATA_URL}#{INDEXFILE}.zip",
          file: "#{INDEXFILE}.yaml",
          pubid_class: ::Pubid::Xsf::Identifier,
        )
      end

      private

      def rows
        return [] unless ref

        index.search(ref) { |row| ref.matches? row[:id] }
          .sort_by { |row| row[:id].to_s }
      end
    end
  end
end
