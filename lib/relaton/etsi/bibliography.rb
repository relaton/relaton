# frozen_string_literal: true

module Relaton
  module Etsi
    # Methods for search IANA standards.
    module Bibliography
      SOURCE = "https://raw.githubusercontent.com/relaton/relaton-data-etsi/refs/heads/v2/"

      # @param text [String]
      # @return [Relaton::Etsi::ItemData, nil]
      def search(text) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
        pubid = parse_pubid(text) or return

        index = Relaton::Index.find_or_create :etsi, url: "#{SOURCE}index-v2.zip", file: INDEX_FILE,
                                                     pubid_class: ::Pubid::Etsi::Identifiers::Base
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
      # (version/date) so a bare `ETSI GS ZSM 012` matches every edition, while a
      # fully-qualified ref matches only that edition (nothing to ignore). The
      # pubid — not a String — is passed to `index.search` so the index narrows
      # candidates by number via binary search before the block runs; each row's
      # `:id` is already a Pubid::Etsi identifier (deserialized via `pubid_class`).
      # `max_by` on the rendered id picks the latest version/date among matches.
      #
      # @note A part-less ref (e.g. `ETSI EN 300 175`) does not yet match its
      #   parts: ETSI pubid keeps the part inside the `code` component, so it
      #   can't be excluded without also dropping the number. Refs normally carry
      #   the part, so this only affects the uncommon all-parts query.
      #
      # @param index [Relaton::Index::Type]
      # @param pubid [::Pubid::Etsi::Identifiers::Base]
      # @return [Hash, nil] the winning index row (`{ id:, file: }`)
      def best_match(index, pubid)
        ignore = %i[version date].select { |attr| pubid.public_send(attr).nil? }
        index.search(pubid) { |row| pubid.matches?(row[:id], ignore: ignore) }
             .max_by { |row| row[:id].to_s }
      end

      # Parse the reference into a Pubid::Etsi identifier, or nil when it can't
      # be parsed. An unrecognized reference reports "not found" rather than
      # raising: the ETSI parser wraps failures as RuntimeError, which the CLI's
      # `Parslet::ParseFailed` handler would not catch. The parser accepts
      # partial refs (bare number, optional version/date), so a valid partial
      # ref parses with version/date left nil.
      #
      # @param text [String]
      # @return [::Pubid::Etsi::Identifiers::Base, nil]
      def parse_pubid(text)
        ::Pubid::Etsi.parse text
      rescue StandardError
        nil
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
