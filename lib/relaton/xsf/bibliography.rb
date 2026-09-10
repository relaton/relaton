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
      # An unrecognized reference **raises**; like ISO, ETSI and 3GPP we let it
      # propagate. relaton-cli rescues `Parslet::ParseFailed` and renders
      # `"..." is not a recognized standards identifier`
      # (`gems/relaton-cli/lib/relaton/cli/command.rb:324`,
      # `subcommand_collection.rb:134`), and `Db#fetch` logs it via the
      # `StandardError` arm at `lib/relaton/db.rb:122`. Rescuing here would
      # collapse "this identifier is malformed" into "no such document", and a
      # caller could no longer tell them apart.
      #
      # There is also deliberately no substring fallback: the old
      # `index.search(ref)` compared a substring of the rendered id, so a bare
      # `001` answered with 11 documents and `#get` took `.first` -- a truncated
      # reference silently resolved to whichever sorted first.
      #
      # @param ref [String] e.g. "XEP 0001", "XEP-0001", "0001"
      #
      # @return [Relaton::Xsf::HitCollection]
      # @raise [Pubid::Errors::ParseError] if the reference is not an XEP id
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
      # Anything else raises -- see `.search`. `Pubid::Errors::ParseError` is a
      # `Parslet::ParseFailed`, which is the class relaton-cli rescues.
      #
      # @param ref [String]
      # @return [Pubid::Xsf::Identifier]
      # @raise [Pubid::Errors::ParseError]
      #
      def parse_ref(ref)
        ::Pubid::Xsf::Identifier.parse normalize_ref(ref)
      end

      private

      def normalize_ref(ref)
        "XEP #{ref.to_s.strip.sub(/\AXEP[-\s]+/i, '')}"
      end
    end
  end
end
