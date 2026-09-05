# frozen_string_literal:true

require "mechanize"

module Relaton
  module Ecma
    # ECMA bibliography module
    module Bibliography
      ENDPOINT = "https://raw.githubusercontent.com/relaton/relaton-data-ecma/refs/heads/v2/"

      class << self
        # @return [Relaton::Index::Type]
        def index
          Relaton::Index.find_or_create(
            :ECMA, url: "#{ENDPOINT}#{INDEXFILE}.zip", file: "#{INDEXFILE}.yaml",
            pubid_class: ::Pubid::Ecma::Identifier
          )
        end

        #
        # Search the index for a reference.
        #
        # **The pubid is passed to `Index::Type#search`, not the string.**
        # `search_candidates` narrows only when the argument is not a `String`,
        # and a block alone never narrows — so the plain string this used to
        # pass disabled the binary search however the index was built.
        # `pubid_class:` on the index alone fixes nothing; both had to change
        # together.
        #
        # A reference pubid cannot parse finds nothing. There is deliberately no
        # substring-scan fallback here (the OGC idiom): an ECMA id renders as
        # `ECMA-262 ed17`, so a substring scan would answer a truncated
        # reference like `ECMA-26` with every ECMA-26x document — an ambiguous
        # answer is worse than none. By the same trade-off, a reference must now
        # parse WHOLE: the old regex was unanchored at the end, so
        # `ECMA-6 (draft)` silently resolved to ECMA-6 and now does not. See
        # lib/relaton/ecma/CLAUDE.md for the measured table.
        #
        # @param ref [String] the ECMA reference (e.g. "ECMA-6", "ECMA-269 ed3 vol2")
        #
        # @return [Array<Hash>] matching index rows
        #
        def search(ref)
          pubid = parse_ref ref
          return [] unless pubid

          index.search(pubid) { |row| pubid.matches? row[:id], ignore: ignored(pubid) }
        end

        #
        # Parse a user reference into a `Pubid::Ecma::Identifier`, or nil.
        #
        # `Pubid::Ecma` takes the space form (`ECMA 6`) as well as the hyphen
        # one, and parses the ` ed<N>` / ` vol<N>` suffixes the old bespoke
        # regex accepted, so every reference shape the flavor has to handle
        # parses without normalization here.
        #
        # @param ref [String]
        # @return [Pubid::Ecma::Identifier, nil]
        #
        def parse_ref(ref)
          ::Pubid::Ecma::Identifier.parse ref.to_s.strip
        rescue StandardError => e
          Util.warn "Failed to parse pubid `#{ref}`: #{e.message}"
          nil
        end

        #
        # The components the reference left out, which a row may carry freely.
        #
        # `edition` and `volume` are the only two: they are index metadata, and
        # a document's own docidentifier carries neither (see
        # `Relaton::Ecma::Docidentifier`), so a bare `ECMA-269` has to reach the
        # edition rows. `number`, `part` and the identifier's CLASS are never
        # ignorable — `matches?` compares the class, which is what keeps
        # `ECMA-100` and `ECMA TR/100` apart.
        #
        # @param pubid [Pubid::Ecma::Identifier]
        # @return [Array<Symbol>]
        #
        def ignored(pubid)
          %i[edition volume].select { |attr| pubid.public_send(attr).nil? }
        end

        # @param code [String] the ECMA standard Code to look up (e..g "ECMA-6")
        # @param year [String] not used
        # @param opts [Hash] not used
        # @return [Relaton::Ecma::ItemData] Relaton of reference
        def get(code, _year = nil, _opts = {})
          Util.info "Fetching from Relaton repository ...", key: code
          result = fetch_doc(code)
          if result
            Util.info "Found: `#{result.docidentifier.first.content}`", key: code
          else
            Util.info "Not found.", key: code
          end
          result
        end

        private

        #
        # The index row for a reference: latest edition, then lowest volume.
        #
        # That is the selection order the bespoke `compare_edition_volume` +
        # `min` implemented, kept deliberately — but the edition is now compared
        # segment-wise as INTEGERS. Comparing the rendered strings made "9" beat
        # "17" and "5" beat "5.1", so 5 of the 421 document families returned an
        # older document than the reference asked for: ECMA-262 answered ed9
        # (2018-06) where ed17 (2026-06) exists, ECMA-74 ed9 (2005-12) where
        # ed22 (2025-12) exists, and likewise 402, 328 and 109.
        #
        # `r[:file]` breaks the tie, because the index sort is not stable.
        #
        # @param ref [String]
        # @return [Hash, nil]
        #
        def best_match(ref)
          search(ref).max_by { |r| [edition_key(r[:id].edition), -r[:id].volume.to_i, r[:file]] }
        end

        #
        # Order key for an ECMA edition: its dot-separated segments as integers.
        #
        # `[]` for an absent edition, which therefore sorts below every present
        # one — right for the 64 edition-less rows (mementos, a few reports),
        # none of which shares a document with an edition-bearing row.
        #
        # @param edition [String, nil]
        # @return [Array<Integer>]
        #
        def edition_key(edition)
          edition.to_s.split(".").map(&:to_i)
        end

        def fetch_doc(code)
          row = best_match code
          return unless row

          url = "#{ENDPOINT}#{row[:file]}"
          resp = Mechanize.new.get(url)
          Item.from_yaml(resp.body).tap { |item| item.fetched = Date.today.to_s }
        rescue Mechanize::ResponseCodeError => e
          return if e.response_code == "404"

          raise Relaton::RequestError, "No document found for #{code} reference. #{e.message}"
        rescue Mechanize::RedirectLimitReachedError, Timeout::Error,
            Mechanize::UnauthorizedError, Mechanize::UnsupportedSchemeError,
            Mechanize::ResponseReadError, Mechanize::ChunkedTerminationError => e
          raise Relaton::RequestError, "No document found for #{code} reference. #{e.message}"
        end
      end
    end
  end
end
