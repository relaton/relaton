# frozen_string_literal: true

require "net/http"
require "relaton/bib/hash_parser_v1"

module Relaton
  module W3c
    # Class methods for search W3C standards.
    class Bibliography
      SOURCE = "https://raw.githubusercontent.com/relaton/relaton-data-w3c/v2/"

      class << self
        # @param text [String]
        # @return [Relaton::W3c::ItemData]
        def search(text)
          # A reference pubid rejects is a miss, not an error: `parse_ref`
          # returns nil rather than raising, so it never becomes a
          # `Relaton::RequestError` from the transport rescue below.
          pubid = parse_ref text
          return unless pubid

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
        # scanned. `date` is W3C's only optional component, so the ETSI idiom
        # (`lib/relaton/etsi/bibliography.rb`) reduces to ignoring it when the
        # reference omits it, which is how an undated `REC-xml-names` still
        # finds the dated row. The maturity level is deliberately NOT
        # ignorable: it is the identifier's class, and `matches?` compares
        # through `exclude` -> `self.class.new(...)`, so `WD-`, `REC-` and a
        # bare slug never match each other — the same contract the bespoke
        # `PubId#==` had for its `stage`/`type`.
        #
        # @param pubid [Pubid::W3c::Identifier]
        # @return [Hash, nil]
        #
        def best_match(pubid)
          ignore = %i[date].select { |attr| pubid.public_send(attr).nil? }
          rows = index.search(pubid) { |r| pubid.matches?(r[:id], ignore: ignore) }
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

        def index
          Relaton::Index.find_or_create(
            :W3C, url: "#{SOURCE}#{INDEXFILE}.zip", file: "#{INDEXFILE}.yaml",
            pubid_class: ::Pubid::W3c::Identifier
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
        def parse_ref(text)
          ::Pubid::W3c::Identifier.parse normalize_ref(text)
        rescue StandardError => e
          Util.warn "Failed to parse pubid `#{text}`: #{e.message}"
          nil
        end

        def normalize_ref(text)
          ref = text.to_s.strip
            .sub(%r{\Ahttps?://[^/]+/}i, "") # a URL is not an identifier
            .sub(/\AW3C\s+/i, "")
            .sub(%r{\ATR[/-]}i, "")          # URL path segment, not a stage
            .sub(%r{/\z}, "")
          "W3C #{ref}"
        end

        # @param ref [String] the W3C standard Code to look up
        # @param year [String, NilClass] not used
        # @param opts [Hash] options
        # @return [Relaton::W3c::ItemData]
        def get(ref, _year = nil, _opts = {})
          Util.info "Fetching from Relaton repository ...", key: ref
          result = search(ref)
          unless result
            Util.info "Not found.", key: ref
            return
          end

          found = result.docidentifier.first.content
          Util.info "Found: `#{found}`", key: ref
          result
        end
      end
    end
  end
end
