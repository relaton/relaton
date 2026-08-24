# frozen_string_literal: true

require "pubid"
require "pubid/ietf"

module Relaton
  module Ietf
    # Scraper module
    module Scraper
      extend Scraper

      # The combined corpus — RFCs, the RFC sub-series and Internet-Drafts in one
      # repo, with one pubid `index-v2` covering all ~177k records (relaton#109).
      # It replaces the three per-type repos this flavor used to read; those keep
      # publishing their `index-v1` for released relatons, untouched.
      IETF = "https://raw.githubusercontent.com/relaton/relaton-data-ietf/main/"

      # @param text [String]
      # @return [Relaton::Ietf::ItemData, nil]
      def scrape_page(text)
        id = parse_id text.sub(/\AIETF\s+/, "")
        return unless id

        fetch_doc id
      rescue Timeout::Error, Errno::EINVAL, Errno::ECONNRESET, EOFError,
             Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError,
             Net::ProtocolError, SocketError
        raise Relaton::RequestError, "No document found for #{text} reference"
      end

      private

      # The index stores parsed pubids, so the query has to be one too.
      # `Type#search_candidates` narrows only when the query is not a String
      # (`@file_io.sorted && id && !id.is_a?(String)`); a String falls through to
      # `match_item`'s `item[:id].to_s.include?(id)`, which renders every pubid in
      # the index on every lookup — measured at ~40 s per reference against the
      # 177k-row index, versus sub-millisecond for a parsed one.
      def fetch_doc(id)
        row = index.search(id).first
        get_page "#{IETF}#{row[:file]}" if row
      end

      def index
        Relaton::Index.find_or_create(
          :IETF, url: "#{IETF}#{INDEXFILE}.zip", file: "#{INDEXFILE}.yaml",
                 pubid_class: ::Pubid::Ietf::Identifier
        )
      end

      #
      # Parse a reference into the identifier the index is keyed by.
      #
      # Normalises the two Internet-Draft spellings callers use — `I-D.<slug>`
      # and `I-D <slug>` — onto the `draft-…` form pubid parses and the index
      # stores. The bare `I-D.ietf-quic-transport` spelling (the bibxml anchor,
      # and the `docnumber` IETF records carry) gains the `draft-` stem: the old
      # plain-string index matched it by substring, and matching is exact now.
      #
      # @param ref [String]
      # @return [Pubid::Ietf::Identifier, nil] nil when pubid has no grammar for
      #   it, so an out-of-flavor reference logs "Not found." instead of raising
      #
      def parse_id(ref)
        if (draft = ref[/\AI-D[.\s]\s*(.+)\z/m, 1])
          ref = draft.start_with?("draft-") ? draft : "draft-#{draft}"
        end
        ::Pubid::Ietf::Identifier.parse ref
      rescue StandardError => e
        # Logged, not swallowed: this repo git-pins pubid to a moving `main`,
        # so a grammar regression would otherwise present as every IETF
        # reference quietly reporting "Not found."
        Util.debug "`#{ref}` is not an IETF identifier: #{e.message}"
        nil
      end

      # @param uri [String]
      # @return [Relaton::Ietf::ItemData, nil] HTTP response body
      def get_page(uri)
        res = Net::HTTP.get_response(URI(uri))
        return unless res.code == "200"

        Item.from_yaml(res.body).tap { |item| item.fetched = Date.today.to_s }
      end
    end
  end
end
