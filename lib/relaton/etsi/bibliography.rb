# frozen_string_literal: true

module Relaton
  module Etsi
    # Methods for search IANA standards.
    module Bibliography
      SOURCE = "https://raw.githubusercontent.com/relaton/relaton-data-etsi/refs/heads/v2/"

      # @param text [String]
      # @return [Relaton::Etsi::ItemData, nil]
      def search(text) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
        # An unrecognized reference raises Parslet::ParseFailed; like ISO we let
        # it propagate — the CLI turns it into a friendly message and API callers
        # rescue it themselves. Valid partial refs parse with the omitted
        # refinements (version/date/part) left blank.
        pubid = ::Pubid::Etsi.parse text

        index = Relaton::Index.find_or_create :etsi, url: "#{SOURCE}#{INDEXFILE}.zip", file: "#{INDEXFILE}.yaml",
                                                     pubid_class: ::Pubid::Etsi::Identifier
        row = best_match(index, pubid)
        return unless row

        url = "#{SOURCE}#{row[:file]}"
        resp = Net::HTTP.get_response URI(url)
        return unless resp.code == "200"

        Item.from_yaml(resp.body).tap { |item| item.fetched = Date.today.to_s }
      rescue SocketError, Timeout::Error, Errno::EINVAL, Errno::ECONNRESET,
             EOFError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError,
             Net::ProtocolError, Errno::ETIMEDOUT => e
        raise Relaton::RequestError, e.message
      end

      # Match the reference against the index and return the most recent edition.
      #
      # The reference is compared as a pubid, ignoring the refinements it omits
      # (version/date, and part when absent) so a bare `ETSI GS ZSM 012` matches
      # every edition and a part-less `ETSI EN 300 175` matches every part, while
      # a fully-qualified ref matches only that edition (nothing to ignore). The
      # pubid — not a String — is passed to `index.search` so the index narrows
      # candidates by number via binary search before the block runs; each row's
      # `:id` is already a Pubid::Etsi identifier (deserialized via `pubid_class`).
      # `max_by` on `edition_key` picks the latest edition among the matches.
      #
      # @param index [Relaton::Index::Type]
      # @param pubid [::Pubid::Etsi::Identifier]
      # @return [Hash, nil] the winning index row (`{ id:, file: }`)
      def best_match(index, pubid)
        ignore = %i[version date].select { |attr| pubid.public_send(attr).nil? }
        ignore << :part if pubid.code&.parts.to_a.empty? # part-less ref → all parts
        index.search(pubid) { |row| pubid.matches?(row[:id], ignore: ignore) }
             .max_by { |row| edition_key(row[:id]) }
      end

      # Sort key for one edition: the version numbers, then the publication date.
      #
      # ETSI versions are not zero-padded, so a comparison of the rendered id
      # orders `V9.0.0` above `V19.0.0` and `ed.9` above `ed.11`, and a bare
      # reference then resolves to an old edition. `Pubid::Etsi::Identifier` is
      # not `Comparable` and its `<=>` returns nil, so the key comes from the
      # parsed components: `version.version` holds the bare numbers (`"19.0.0"`,
      # or `"9"` for the `ed.9` form) and `date` renders as `yyyy-mm`. Both
      # delegate to `base` on a corrigendum/amendment id, so every row shape
      # keys the same way. A missing version or date gives `[]` / `""`, which
      # sort below any real value — hence the `.to_s` outside each `&.` chain.
      #
      # @param id [::Pubid::Etsi::Identifier]
      # @return [Array(Array<Integer>, String)]
      def edition_key(id)
        [(id.version&.version).to_s.split(".").map(&:to_i), id.date.to_s]
      end

      # @param ref [String] the ETSI standard Code to look up
      # @param year [String, nil] year
      # @param opts [Hash] options
      # @return [Relaton::Etsi::ItemData, nil]
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

      extend Bibliography
    end
  end
end
