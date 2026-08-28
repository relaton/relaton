require "net/http"

module Relaton
  module Iala
    module Bibliography
      ENDPOINT = "https://raw.githubusercontent.com/relaton/relaton-data-iala/main/".freeze

      class << self
        # Search for an IALA publication by its identifier.
        #
        # @param text [String] the IALA reference to look up (e.g. "IALA S1070")
        # @param _year [String, nil] optional edition/year filter
        # @param _opts [Hash] options (unused)
        # @return [Relaton::Iala::Item, nil]
        def search(text, _year = nil, _opts = {})
          Util.info "Fetching from Relaton repository ...", key: text
          row = best_match text
          unless row
            Util.info "Not found.", key: text
            return
          end

          uri = URI("#{ENDPOINT}#{row[:file]}")
          resp = Net::HTTP.get_response uri
          unless resp.code == "200"
            raise Relaton::RequestError, "Could not access #{uri}: HTTP #{resp.code}"
          end

          item = Relaton::Iala::Item.from_yaml resp.body
          Util.info "Found: `#{item.docidentifier.first&.content}`", key: text
          item.tap { |i| i.fetched = Date.today.to_s }
        rescue SocketError, Errno::EINVAL, Errno::ECONNRESET, EOFError,
               Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError,
               Net::ProtocolError, Net::ReadTimeout, OpenSSL::SSL::SSLError,
               Errno::ETIMEDOUT => e
          raise Relaton::RequestError, "Could not access #{uri}: #{e.message}"
        end

        def get(ref, year = nil, opts = {})
          search(ref, year, opts)
        end

        private

        #
        # Find the index row for a reference, newest edition first.
        #
        # Passing the pubid to `Index::Type#search` is what enables the binary
        # search on `id.root.number` — with a block alone, or with the plain
        # string this used to pass, the whole index is scanned. `edition` and
        # `language` are IALA's only optional components, so the ETSI idiom
        # reduces to ignoring each one the reference omits: that is how a bare
        # `IALA M0001` still finds the `Ed 9.0 (E)` row. The document type is
        # deliberately NOT ignorable — it is the identifier's class, and 17 of
        # the 309 index numbers are shared by two types, so `R1001` and `C1001`
        # must never match each other.
        #
        # A reference pubid cannot parse falls back to the previous behaviour,
        # a full scan matching `id.to_s` as a substring.
        #
        # @param text [String]
        # @return [Hash, nil]
        #
        def best_match(text)
          pubid = parse_ref text
          rows = if pubid
                   index.search(pubid) { |r| pubid.matches?(r[:id], ignore: ignored(pubid)) }
                 else
                   index.search text
                 end
          rows.max_by { |r| [edition_key(r[:id].edition), language_key(r[:id]), r[:file]] }
        end

        # The components the reference left out, which the row may therefore
        # carry freely.
        #
        # @param pubid [Pubid::Iala::Identifier]
        # @return [Array<Symbol>]
        #
        def ignored(pubid)
          %i[edition language].select { |attr| pubid.public_send(attr).nil? }
        end

        #
        # Order key for an IALA edition.
        #
        # Editions are dotted version strings, so they must be compared segment
        # by segment as integers rather than as text: `"10.0"` is newer than
        # `"9.0"` but sorts before it as a string. No published edition has a
        # segment above 9 today, so this is a latent bug rather than a live one
        # — the same one already fixed for ETSI. An absent edition sorts below
        # every present one.
        #
        # `2` and `2.0` are distinct editions in the index and compare as
        # `[2] < [2, 0]`; `2.02` and `2.2` reduce to the same segments. Both
        # pairs are broken by the edition text and then the file path, so a
        # repeated lookup returns the same document (the index sort is not
        # stable).
        #
        # @param edition [String, nil]
        # @return [Array]
        #
        def edition_key(edition)
          [edition.to_s.split(".").map(&:to_i), edition.to_s]
        end

        # Prefer the language-neutral record over its translations: it is the
        # base document, and the translations are keyed off it.
        #
        # @param row_id [Pubid::Iala::Identifier]
        # @return [Integer]
        #
        def language_key(row_id)
          row_id.language.nil? ? 1 : 0
        end

        #
        # Parse a user reference into a `Pubid::Iala::Identifier`, or nil.
        #
        # `Pubid::Iala` takes the `IALA ` publisher prefix as optional and
        # zero-pads the number to its type's canonical width, so `IALA M1`,
        # `M0001` and `R1016:ed2.0(F)` all parse without normalization here.
        #
        # @param text [String]
        # @return [Pubid::Iala::Identifier, nil]
        #
        def parse_ref(text)
          ::Pubid::Iala::Identifier.parse text.to_s.strip
        rescue StandardError => e
          Util.warn "Failed to parse pubid `#{text}`: #{e.message}"
          nil
        end

        # The index is pubid-backed: `pubid_class:` is what makes
        # Relaton::Index deserialize the rows into identifiers, sort them by
        # `id.root.number`, and let `Type#search` bsearch. Without it the rows
        # stay raw hashes and every lookup scans all 701 of them.
        def index
          Relaton::Index.find_or_create(
            :iala,
            url: "#{ENDPOINT}#{INDEXFILE}.zip",
            file: "#{INDEXFILE}.yaml",
            pubid_class: ::Pubid::Iala::Identifier,
          )
        end
      end
    end
  end
end
