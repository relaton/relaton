module Relaton
  module Xsf
    module Bibliography
      extend self

      #
      # Search the index for a reference.
      #
      # The reference is parsed into a `Pubid::Xsf::Identifier` here and the
      # identifier -- never the string -- is what reaches `HitCollection`.
      # `Index::Type#search_candidates` narrows only when its argument is not a
      # `String`, so parsing at the entry point is what lets the lookup binary
      # search; `Core::HitCollection` takes a `String` or a pubid by design.
      #
      # A reference pubid cannot parse finds nothing, with a warning. There is
      # deliberately no substring fallback: the old `index.search(ref)` compared
      # a substring of the rendered id, so a bare `001` answered with 11
      # documents and `#get` took `.first` -- a truncated reference silently
      # resolved to whichever sorted first.
      #
      # @param ref [String] e.g. "XEP 0001", "XEP-0001", "0001"
      #
      # @return [Relaton::Xsf::HitCollection]
      #
      def search(ref)
        HitCollection.new(parse_ref(ref)).search
      end

      def get(code, _year = nil, _opts = {})
        Util.info "Fetching from Relaton repository ...", key: code
        result = search(code)
        if result.empty?
          Util.info "Not found.", key: code
          return
        end

        bib = result.first.item
        Util.info "Found: `#{bib.docidentifier.first.content}`", key: code
        bib
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
      # The token match is case-insensitive, so `xep 0001` resolves too.
      #
      # @param ref [String]
      # @return [Pubid::Xsf::Identifier, nil]
      #
      def parse_ref(ref)
        ::Pubid::Xsf::Identifier.parse normalize_ref(ref)
      rescue StandardError => e
        Util.warn "Failed to parse pubid `#{ref}`: #{e.message}"
        nil
      end

      private

      def normalize_ref(ref)
        "XEP #{ref.to_s.strip.sub(/\AXEP[-\s]+/i, '')}"
      end
    end
  end
end
