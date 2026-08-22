# frozen_string_literal: true

module Relaton
  module Iana
    # Retrieval front-end for the IANA flavor. Parses the citation with
    # Pubid::Iana, looks it up in the pubid-structured `relaton-data-iana`
    # index-v2, and fetches the matching per-document YAML over HTTP.
    #
    # An IANA entry is a protocol registry, not a numbered standard: the
    # identifier is a registry slug with at most one "/"
    # (`IANA _6lowpan-parameters`, `IANA _6lowpan-parameters/lowpan_nhc`). The
    # index rows key on the TOP-LEVEL slug (`Identifiers::Registry#number`), so
    # a registry and all of its sub-registries share one bsearch bucket and the
    # block below distinguishes them.
    module Bibliography
      SOURCE = "https://raw.githubusercontent.com/relaton/relaton-data-iana/refs/heads/v2/"

      # @param text [String, Pubid::Iana::Identifier]
      # @return [Relaton::Iana::Item, nil]
      def search(text)
        pubid = parse_ref text
        return unless pubid

        # Pass the pubid so Relaton::Index narrows candidates by number via
        # binary search before applying the block. The match is exact, so there
        # is at most one row.
        row = index.search(pubid) { |r| pubid_match? r[:id], pubid }.first
        return unless row

        fetch_row row
      rescue SocketError, Timeout::Error, Errno::EINVAL, Errno::ECONNRESET,
             EOFError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError,
             Net::ProtocolError, Errno::ETIMEDOUT => e
        raise Relaton::RequestError, e.message
      end

      # @param ref [String] the IANA registry slug to look up
      # @param year [String, NilClass] not used
      # @param opts [Hash] options
      # @return [Relaton::Iana::Item, nil]
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

      def index
        Relaton::Index.find_or_create :iana, url: "#{SOURCE}#{INDEXFILE}.zip",
                                             file: "#{INDEXFILE}.yaml",
                                             pubid_class: ::Pubid::Iana::Identifier
      end

      # `Pubid::Iana::Identifier.parse` accepts both the printed `IANA <slug>`
      # form and the bare slug the index rows render back to. It raises a plain
      # RuntimeError on anything else, and a citation relaton cannot parse is a
      # miss, not an error — `#get` reports it as "Not found.".
      #
      # @param text [String, Pubid::Iana::Identifier]
      # @return [Pubid::Iana::Identifier, nil]
      def parse_ref(text)
        return text unless text.is_a? String

        ::Pubid::Iana::Identifier.parse text
      rescue StandardError => e
        Util.warn "Failed to parse pubid `#{text}`: #{e.message}"
        nil
      end

      # Both arguments are Pubid::Iana identifiers. Compared field by field
      # rather than with `==` so the two identity fields are explicit: a bare
      # registry must NOT match its own sub-registries, which share its bsearch
      # bucket. (index-v1 matched by substring, so `IANA rpki` also hit
      # `rpki/signed-objects` and `min_by` picked the shortest id.)
      def pubid_match?(row_id, query)
        row_id.class == query.class &&
          row_id.number == query.number &&
          row_id.sub_registry.to_s == query.sub_registry.to_s
      end

      # @param row [Hash] an index row
      # @return [Relaton::Iana::Item, nil]
      def fetch_row(row)
        resp = Net::HTTP.get_response URI("#{SOURCE}#{row[:file]}")
        return unless resp.code == "200"

        Item.from_yaml(resp.body).tap { |item| item.fetched = Date.today.to_s }
      end

      extend self
    end
  end
end
