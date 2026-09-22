# frozen_string_literal: true

module Relaton
  module Etsi
    # Methods for search IANA standards.
    module Bibliography
      SOURCE = "https://raw.githubusercontent.com/relaton/relaton-data-etsi/refs/heads/v2/"

      # @param text [String]
      # @return [Relaton::Etsi::ItemData, nil]
      def search(text) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
        # An unrecognized reference raises Pubid::Errors::ParseError; like
        # ISO we let it propagate — the CLI turns it into a friendly message
        # and API callers rescue it themselves. Valid partial refs parse with
        # the omitted refinements (version/date/part) left blank.
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
      # The rows are selected with pubid's subset match `pubid === row`. A
      # version or a date that the reference omits matches any value, so a
      # bare `ETSI GS ZSM 012` matches every edition, while a fully-qualified
      # ref matches only that edition. The class must be identical, so a base
      # reference such as `ETSI ETR 310` does not reach its amendment or
      # corrigendum (`ETR 310/C1`).
      # The pubid — not a String — is passed to `index.search` so the index
      # narrows candidates by number via binary search; each row's `:id` is
      # already a Pubid::Etsi identifier (deserialized via `pubid_class`).
      # `max_by` on `edition_key` picks the latest edition among the matches.
      #
      # pubid declares `parts` strict for ETSI, so a part-less reference asks
      # for every part by matching each row **without its parts** (see
      # #comparable). `#to_all_parts` cannot serve here: a
      # `Pubid::AllPartsIdentifier` compares the document alone, so it also
      # drops the version and the date, and
      # `ETSI GR ZSM 011 V1.1.1 (2023-02)` would answer with V2.1.1.
      #
      # @param index [Relaton::Index::Type]
      # @param pubid [::Pubid::Etsi::Identifier]
      # @return [Hash, nil] the winning index row (`{ id:, file: }`)
      def best_match(index, pubid)
        all_parts = pubid.code&.parts.to_a.empty?
        index.search(pubid) { |row| pubid === comparable(row[:id], all_parts) }
             .max_by { |row| edition_key(row[:id]) }
      end

      # The row as the reference sees it: without its parts when the reference
      # names none, unchanged otherwise. `#exclude` returns a copy, so the
      # cached index id is untouched.
      #
      # @param id [::Pubid::Etsi::Identifier]
      # @param all_parts [Boolean] the reference names no part
      # @return [::Pubid::Etsi::Identifier]
      def comparable(id, all_parts)
        all_parts ? id.exclude(:part, :subpart, :parts) : id
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
