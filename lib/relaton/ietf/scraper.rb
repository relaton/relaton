# frozen_string_literal: true

require "pubid"
require "pubid/ietf"
require_relative "bibxml_parser"

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

      # The IETF bibxml service, read when the index has no row for a versioned
      # Internet-Draft (relaton-ietf#125). The data repo crawls the rsync
      # `bibxml-ids` snapshot, which keeps only some versions of each draft
      # (`draft-ietf-vcarddav-vcardrev`: only -22); this service resolves any
      # version the datatracker knows, and answers 404 for one it does not.
      BIBXML_IDS = "https://bib.ietf.org/public/rfc/bibxml-ids/"

      # @param ref [String, Pubid::Ietf::Identifier] a reference, or its parse
      #   from Relaton::Db (relaton#205), which is used as it is
      # @return [Relaton::Ietf::ItemData, nil]
      def scrape_page(ref)
        id = ref.is_a?(String) ? parse_id(ref.sub(/\AIETF\s+/, "")) : ref
        return unless id

        fetch_doc id
      rescue Timeout::Error, Errno::EINVAL, Errno::ECONNRESET, EOFError,
             Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH,
             OpenSSL::SSL::SSLError, Net::HTTPBadResponse,
             Net::HTTPHeaderSyntaxError, Net::ProtocolError, SocketError
        raise Relaton::RequestError, "No document found for #{ref} reference"
      end

      private

      # The index stores parsed pubids, so the query has to be one too.
      # `Type#search_candidates` narrows only when the query is not a String
      # (`@file_io.sorted && id && !id.is_a?(String)`); a String falls through to
      # `match_item`'s `item[:id].to_s.include?(id)`, which renders every pubid in
      # the index on every lookup — measured at ~40 s per reference against the
      # 177k-row index, versus sub-millisecond for a parsed one.
      # `exact:` keeps the match exact. `Type#search` without it takes
      # pubid's subset match, where a component the query omits is a wildcard —
      # and an Internet-Draft slug omits the version, so `draft-foo` would match
      # every `draft-foo-NN` and `.first` would return an arbitrary one (20,513
      # such pairs in the first 40k rows of the index fixture).
      def fetch_doc(id)
        row = index.search(id, exact: true).first
        return get_page "#{IETF}#{row[:file]}" if row

        fetch_bibxml id if versioned_draft? id
      end

      # Only a versioned draft falls back. The index holds every RFC, sub-series
      # and unversioned draft aggregator the data repo has, so a miss on one of
      # those is a real "not found", and bib.ietf.org has no aggregator to offer.
      def versioned_draft?(id)
        id.is_a?(::Pubid::Ietf::Identifiers::InternetDraft) && !id.version.to_s.empty?
      end

      #
      # Read one draft version from bib.ietf.org and parse it the way
      # `DataFetcher#process_singleton` parses a crawled file: the same
      # CP1252 repair, the same parser, and the version from the identifier.
      #
      # A 404 is the service's "no such version". Any other non-200 (a 429, a
      # 5xx) is push-back or an outage, so it raises `Relaton::RequestError`:
      # `Db#net_retry` then retries it, and the Db cache does not store it as a
      # not-found.
      #
      # @param id [Pubid::Ietf::Identifiers::InternetDraft]
      # @return [Relaton::Ietf::ItemData, nil] nil on a 404 or an unreadable body
      #
      def fetch_bibxml(id)
        res = Net::HTTP.get_response URI("#{BIBXML_IDS}reference.I-D.#{id}.xml")
        return if res.code == "404"
        raise Relaton::RequestError, "#{BIBXML_IDS} answered #{res.code} for #{id}" unless res.code == "200"

        bib = parse_bibxml(res.body, id)
        return unless bib

        bib.version = [Bib::Version.new(draft: id.version.to_s)]
        bib.fetched = Date.today.to_s
        bib
      end

      # A 200 that is not bibxml (an HTML error page, a truncated body) costs
      # this one document, not the caller's compile. These are the errors the
      # parse raises on such a body: lutaml's `InvalidFormatError`, and the
      # converter's `NoMethodError` on a document with no `<front>` and
      # `ArgumentError` from its regexes. They are named, not `StandardError`,
      # so a transport error still reaches `scrape_page`'s rescue.
      def parse_bibxml(body, id)
        BibXMLParser.parse BibXMLParser.to_utf8(body)
      rescue Lutaml::Model::InvalidFormatError, NoMethodError, ArgumentError => e
        Util.warn "Unreadable bibxml for `#{id}`: #{e.message.to_s.lines.first.to_s.strip}"
        nil
      end

      #
      # The machine index on the Pages site (relaton#206, the W3C pilot's
      # contract): a parsed query reads only its own shard. A Pages failure
      # raises `Relaton::RequestError`; the whole-index zip on the same site
      # serves only the case-insensitive retry on a miss.
      #
      def index
        Relaton::Index.find_or_create(
          :IETF, pages_url: PAGES_URL, pubid_class: ::Pubid::Ietf::Identifier
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
      # The capture is `(\S.*)`, not `(.+)`: it must start non-space so it cannot
      # overlap the preceding `\s*`. Behaviour is unchanged on every real
      # reference — with `(.+)` the greedy `\s*` only ever yields ground on an
      # all-whitespace remainder, which pubid rejects anyway — but the
      # unambiguous form is about twice as fast on a pathological input and is
      # what CodeQL's rb/polynomial-redos models. Measured before changing it:
      # the old form was already linear (0.66 ms at 80k chars), so this is
      # clarity, not a ReDoS fix.
      #
      # @param ref [String]
      # @return [Pubid::Ietf::Identifier, nil] nil when pubid has no grammar for
      #   it, so an out-of-flavor reference logs "Not found." instead of raising
      #
      def parse_id(ref)
        if (draft = ref[/\AI-D[.\s]\s*(\S.*)\z/m, 1])
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
