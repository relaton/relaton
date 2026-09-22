# frozen_string_literal: true

module Relaton
  module ThreeGpp
    # Methods for search 3GPP standards.
    module Bibliography
      SOURCE = "https://raw.githubusercontent.com/relaton/relaton-data-3gpp/v2/"

      # @param text [String]
      # @return [Relaton::ThreeGpp::ItemData, nil]
      def search(text)
        # An unrecognized reference raises; like ISO and ETSI we let it
        # propagate — relaton-cli rescues Pubid::Errors::Error and renders
        # "… is not a recognized standards identifier", and API callers rescue
        # it themselves. The rescue below lists transport errors only, so it
        # does not swallow the parse error.
        pubid = ::Pubid::Tgpp::Identifier.parse text.to_s.strip
        row = best_match pubid
        return unless row

        url = "#{SOURCE}#{row[:file]}"
        resp = Net::HTTP.get_response URI(url)
        return unless resp.code == "200"

        item = Item.from_yaml(resp.body)
        item.fetched = Date.today.to_s
        item
      rescue  SocketError, Timeout::Error, Errno::EINVAL, Errno::ECONNRESET,
              EOFError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError,
              Net::ProtocolError, Errno::ETIMEDOUT => e
        raise Relaton::RequestError, e.message
      end

      # @param ref [String] the 3GPP standard Code to look up
      # @param year [String, NilClass] not used
      # @param opts [Hash] options
      # @return [Relaton::ThreeGpp::ItemData, nil]
      def get(ref, _year = nil, _opts = {})
        Util.info "Fetching from Relaton repository ...", key: ref
        result = search(ref)
        unless result
          Util.info "Not found.", key: ref
          return
        end

        Util.info "Found: `#{result.docidentifier[0].content}`", key: ref
        result
      end

      private

      #
      # Find the index row for a reference, newest version first.
      #
      # Passing the pubid to `Index::Type#search` is what enables the binary
      # search on `id.root.number` — `Type#search_candidates` narrows only when
      # its argument is NOT a String, so the plain text this used to pass
      # disabled the narrowing however the index was built. With 88,464 rows in
      # 3,767 number buckets that is the whole point of the index-v2 migration.
      #
      # The rows are selected with pubid's subset match `pubid === row`, the
      # default of `Index::Type#search`. `release` and `version` are 3GPP's
      # only optional components: when the reference omits one, it matches
      # any value, so a bare `3GPP TS 23.207` still finds the `REL-19/19.0.0`
      # row. pubid declares `suffix` and `parts` strict for 3GPP, because they
      # are part of the document code (`TS 29.198-04-1`, `TR 00.01U`), not
      # qualifiers. The document type is the identifier's class, and `===`
      # requires the same class, so `TS 23.207` and `TR 23.207` never match.
      #
      # @param pubid [::Pubid::Tgpp::Identifier]
      # @return [Hash, nil] the winning index row (`{ id:, file: }`)
      #
      def best_match(pubid)
        index.search(pubid)
             .max_by { |r| [version_key(r[:id].version), r[:id].to_s, r[:file]] }
      end

      #
      # Order key for a 3GPP version — the highest version wins.
      #
      # Versions are dotted strings, so they must be compared segment by
      # segment as integers rather than as text: `19.0.0` is newer than
      # `4.0.0` but loses as a string. This is a deliberate behaviour change.
      # The previous key, `min_by { r[:id] }` over raw strings, returned
      # `REL-10/10.0.0` for `3GPP TS 23.207` — neither the newest nor the
      # oldest of its 37 rows, just whichever sorted first as text. Scored
      # against each document's own publication date over 870 documents in 59
      # multi-row groups, this key picks the newest published document 51/59
      # (86%) of the time; the old one managed 1/59 (2%).
      #
      # No release key is layered on top. Ranking releases numerically is wrong
      # (the chronological order is Ph1, Ph2, REL-96 … REL-99, Release 2000,
      # UMTS, REL-4 … REL-21, so REL-99 would outrank REL-19) and a
      # hand-maintained 27-token table would disagree with this key on only 9
      # of 3,982 multi-row groups — all draft TRs carried into a later release
      # at a lower version, where the release answer is not clearly better.
      #
      # An absent version sorts below every present one. Ties break on the
      # rendered id and then the file path, because the index sort is not
      # stable.
      #
      # @param version [String, nil]
      # @return [Array<Integer>]
      #
      def version_key(version)
        version.to_s.split(".").map(&:to_i)
      end

      # The index is pubid-backed: `pubid_class:` is what makes Relaton::Index
      # deserialize the rows into identifiers, sort them by `id.root.number`,
      # and let `Type#search` bsearch. Without it the rows stay raw hashes,
      # `FileIO#sorted` stays false, and every lookup scans all 88,464 of them.
      def index
        Relaton::Index.find_or_create(
          "3GPP", url: "#{SOURCE}#{INDEXFILE}.zip", file: "#{INDEXFILE}.yaml",
          pubid_class: ::Pubid::Tgpp::Identifier
        )
      end

      extend Bibliography
    end
  end
end
