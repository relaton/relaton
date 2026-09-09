module Relaton
  module Xsf
    class HitCollection < Relaton::Core::HitCollection
      GHDATA_URL = "https://raw.githubusercontent.com/relaton/relaton-data-xsf/v2/".freeze

      def search
        pubid = parse_ref ref
        rows = pubid ? matching_rows(pubid) : []
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

      #
      # The index rows a reference matches, newest-numbered last.
      #
      # Passing the pubid to `Index::Type#search` is what enables the binary
      # search on `id.root.number` — with the plain string this used to pass,
      # the whole index is scanned however the index was built.
      #
      # An XEP identifier is only a publisher and a number: there is no
      # edition, no date, no part. So nothing is ignorable and `matches?` is a
      # plain equality — which is the point of the change. The old
      # `index.search(ref)` did a **substring** match on the rendered id, so a
      # bare `001` answered with 11 documents (`XEP 0001` and every `XEP 001x`).
      # `Bibliography#get` then took `.first`, so a loose reference silently
      # resolved to whichever sorted first.
      #
      # @param pubid [Pubid::Xsf::Identifier]
      # @return [Array<Hash>]
      #
      def matching_rows(pubid)
        index.search(pubid) { |row| pubid.matches? row[:id] }
          .sort_by { |row| row[:id].to_s }
      end

      #
      # Parse a user reference into a `Pubid::Xsf::Identifier`, or nil.
      #
      # `Pubid::Xsf` accepts only the canonical `XEP 0001` spelling, so two
      # forms are normalized first:
      #
      # - **`XEP-0001`**, the spelling xmpp.org itself uses everywhere. It did
      #   not resolve before either (the substring match compared against
      #   `XEP 0001`, which has a space), so this is new support rather than a
      #   preserved behaviour.
      # - **A bare `0001`**, which the substring match did resolve, so it has to
      #   keep working. The publisher token is added, the W3C idiom.
      #
      # @param text [String]
      # @return [Pubid::Xsf::Identifier, nil]
      #
      def parse_ref(text)
        ::Pubid::Xsf::Identifier.parse normalize_ref(text)
      rescue StandardError => e
        Util.warn "Failed to parse pubid `#{text}`: #{e.message}"
        nil
      end

      def normalize_ref(text)
        ref = text.to_s.strip.sub(/\AXEP[-\s]+/i, "")
        "XEP #{ref}"
      end
    end
  end
end
