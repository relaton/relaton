# frozen_string_literal: true

require "net/http"
require "relaton/bib/hash_parser_v1"

module Relaton
  module W3c
    # Class methods for search W3C standards.
    class Bibliography
      SOURCE = "https://raw.githubusercontent.com/relaton/relaton-data-w3c/v2/"
      # The Pages site of the data repo: it serves the machine index (manifest
      # and shards) that `#index` reads. The documents still come from SOURCE.
      PAGES_URL = "https://relaton.github.io/relaton-data-w3c/"

      class << self
        # @param ref [String, Pubid::W3c::Identifier] a reference, or one
        #   already parsed (relaton#189: `Relaton::Db` parses it once)
        # @return [Relaton::W3c::ItemData]
        def search(ref)
          # A reference pubid rejects raises `Pubid::Errors::ParseError`, which
          # the transport rescue below does not catch.
          pubid = ref.is_a?(::Pubid::W3c::Identifier) ? ref : parse_ref(ref)

          row = best_match pubid
          return unless row

          url = "#{SOURCE}#{row[:file]}"
          resp = Net::HTTP.get_response(URI.parse(url))
          return unless resp.code == "200"

          Item.from_yaml(resp.body).tap { |i| i.fetched = Date.today.to_s }
        rescue SocketError, Timeout::Error, Errno::EINVAL, Errno::ECONNRESET,
               EOFError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError,
               Net::ProtocolError, Errno::ETIMEDOUT => e
          raise Relaton::RequestError, "Could not access #{url}: #{e.message}"
        end

        #
        # Find the index row for a reference, newest edition first.
        #
        # Passing the pubid to `Index::Type#search` is what enables the binary
        # search on `id.root.number` — with a block alone the whole index is
        # scanned. Selection is `Type#search`'s default with no block — pubid's
        # asymmetric subset match (`Pubid::SubsetMatch`): the reference on the
        # left, the row on the right, and a component it omits matches any
        # value. `date`
        # is W3C's only optional component, so an undated `REC-xml-names` still
        # finds the dated row, while a dated reference reaches only its own.
        # The maturity level is deliberately NOT a wildcard: it is the
        # identifier's class, and `===` requires the same class, so `WD-`,
        # `REC-` and a bare slug never match each other — the same contract the
        # bespoke `PubId#==` had for its `stage`/`type`.
        #
        # @param pubid [Pubid::W3c::Identifier]
        # @return [Hash, nil]
        #
        def best_match(pubid)
          rows = index.search(pubid)
          rows = index.search { |r| loose_match? r[:id], pubid } if rows.empty?

          # Newest edition wins. Undated rows all score 0, so the file path
          # breaks the tie and a repeated lookup returns the same document
          # (the index sort is not stable).
          rows.max_by { |r| [date_key(r[:id].date), r[:file]] }
        end

        #
        # Order key for a W3C publication date.
        #
        # The dates are opaque digit runs of varying width, so a plain `to_i`
        # does not order them: a legacy 6-digit `YYMMDD` always loses to an
        # 8-digit `YYYYMMDD`, however much later it is (`980619` is June 1998,
        # `19980512` is May). Restoring the century fixes that — all 63
        # 6-digit dates in the corpus are 1990s.
        #
        # Everything else keeps `to_i`, deliberately. The 21 legacy 4-digit
        # `MMDD` dates carry no year and cannot be ordered against a real one
        # at all; as small integers they land below every dated row and above
        # an undated one, which is where `to_i` already put them.
        #
        # @param date [String, nil]
        # @return [Integer]
        #
        def date_key(date)
          str = date.to_s
          str.length == 6 ? "19#{str}".to_i : str.to_i
        end

        #
        # The narrowed range cannot serve a reference whose slug differs from
        # the row's only by case: the bsearch key is case-sensitive. The
        # bespoke `PubId#==` compared its `code` with `casecmp?`, so a full
        # scan repeats the match case-insensitively rather than lose that.
        # (The BIPM `search_index` precedent.)
        #
        # @param row_id [Pubid::W3c::Identifier]
        # @param pubid [Pubid::W3c::Identifier]
        # @return [Boolean]
        #
        def loose_match?(row_id, pubid)
          row_id.instance_of?(pubid.class) &&
            row_id.number.to_s.casecmp?(pubid.number.to_s) &&
            (pubid.date.nil? || row_id.date == pubid.date)
        end

        #
        # The machine index on the Pages site (relaton#189, W3C is the pilot).
        # A parsed query reads only its own shard; the whole index is read, in
        # memory, only by the case-insensitive fallback in `#best_match`.
        # A Pages failure raises `Relaton::RequestError`, with no fallback to
        # the `index-v2.zip` in the data repo.
        #
        def index
          Relaton::Index.find_or_create(
            :W3C, pages_url: PAGES_URL, pubid_class: ::Pubid::W3c::Identifier
          )
        end

        #
        # Parse a user reference into a `Pubid::W3c::Identifier`, or nil.
        #
        # A search string is a query, not a document identifier field, so it
        # does not go through `Docidentifier`: it has to absorb two forms the
        # bespoke regex accepted and a pubid grammar should not. A URL is not
        # an identifier (`https://www.w3.org/TR/xml-names/`), and `TR` is a
        # path segment of that URL rather than a maturity level, so
        # `TR-vocab-adms` means the document `vocab-adms`. The publisher
        # prefix is added when absent, because `Pubid::W3c` requires it.
        #
        # @param text [String]
        # @return [Pubid::W3c::Identifier, nil]
        #
        # An unrecognized reference **raises**; like ISO, ETSI and 3GPP we let it
        # propagate. relaton-cli rescues `Pubid::Errors::Error` and renders
        # `"..." is not a recognized standards identifier`
        # (`gems/relaton-cli/lib/relaton/cli/command.rb:324`), and `Db#fetch`
        # logs it through the `StandardError` arm at `lib/relaton/db.rb:122`.
        # Rescuing here would collapse "this identifier is malformed" into "no
        # such document", leaving a caller unable to tell them apart.
        def parse_ref(text)
          ::Pubid::W3c::Identifier.parse normalize_ref(text)
        end

        def normalize_ref(text)
          ref = text.to_s.strip
            .sub(%r{\Ahttps?://[^/]+/}i, "") # a URL is not an identifier
            .sub(/\AW3C\s+/i, "")
            .sub(%r{\ATR[/-]}i, "")          # URL path segment, not a stage
            .sub(%r{/\z}, "")
          "W3C #{ref}"
        end

        # @param ref [String, Pubid::W3c::Identifier] the W3C standard Code
        #   to look up, or its parsed identifier
        # @param year [String, NilClass] not used
        # @param opts [Hash] options
        # @return [Relaton::W3c::ItemData]
        def get(ref, _year = nil, _opts = {})
          key = ref.to_s
          Util.info "Fetching from Relaton repository ...", key: key
          result = search(ref)
          unless result
            Util.info "Not found.", key: key
            return
          end

          found = result.docidentifier.first.content
          Util.info "Found: `#{found}`", key: key
          result
        end
      end
    end
  end
end
