# frozen_string_literal: true

require "net/http"

module Relaton
  module Oasis
    module Bibliography
      ENDPOINT = "https://raw.githubusercontent.com/relaton/relaton-data-oasis/refs/heads/v2/"

      # The publisher token every OASIS printed id starts with, and the one
      # thing `Pubid::Oasis`'s grammar requires. See #parse_ref.
      PREFIX = "OASIS "

      # The components a reference may omit. `number` (the specification name)
      # is deliberately absent — see #ignored.
      OPTIONAL = %i[version stage part label].freeze

      class << self
        def search(text, _year = nil, _opts = {}) # rubocop:disable Metrics/MethodLength
          Util.info "Fetching from Relaton repository ...", key: text
          row = find_index_entry(text)
          unless row
            Util.info "Not found.", key: text
            return
          end

          uri = URI("#{ENDPOINT}#{row[:file]}")
          parse_item(fetch_yaml(uri), text)
        rescue SocketError, Errno::EINVAL, Errno::ECONNRESET, EOFError,
               Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError,
               Net::ProtocolError, Net::ReadTimeout,
               OpenSSL::SSL::SSLError, Errno::ETIMEDOUT => e
          raise Relaton::RequestError,
                "Could not access #{uri}: #{e.message}"
        end

        def get(ref, year = nil, opts = {})
          search(ref, year, opts)
        end

        private

        #
        # The pubid `index-v2`. `pubid_class:` is what makes `Relaton::Index`
        # deserialize the rows into identifiers, sort them by
        # `id.root.number`, and let `Type#search` bsearch; `file:` names the
        # local cache, and matching it against the producer's own
        # `find_or_create` keeps one pooled `:OASIS` entry rather than two that
        # evict each other.
        #
        # @return [Relaton::Index::Type]
        #
        def index
          Relaton::Index.find_or_create(
            :oasis, url: "#{ENDPOINT}#{INDEXFILE}.zip",
            file: "#{INDEXFILE}.yaml",
            pubid_class: ::Pubid::Oasis::Identifier
          )
        end

        #
        # Find the row that best answers a reference.
        #
        # **Pass the pubid, not the string.** `Type#search_candidates` narrows
        # only when the argument is not a `String`, so passing the reference
        # text would disable the binary search however the index was built.
        #
        # A reference pubid cannot parse finds nothing, and there is no
        # substring fallback. `#parse_ref` supplies the publisher token, so
        # after normalization the only unparseable inputs are a blank string
        # and one over pubid's 1000-character cap — and a substring scan for
        # `""` matches every row in the index, which is worse than a miss.
        # This is also the v1 -> v2 semantic change IANA recorded: v1 matched
        # by substring, so `OASIS amqp` resolved to some `amqp-core` record;
        # v2 matches identifiers, so a partial name no longer resolves.
        #
        # @param text [String] the reference as the caller wrote it
        # @return [Hash, nil] the index row, or nil
        #
        def find_index_entry(text)
          pubid = parse_ref text
          return unless pubid

          rows = index.search(pubid) do |row|
            pubid.matches? row[:id], ignore: ignored(pubid)
          end
          rows.max_by { |row| ranking_key pubid, row[:id] }
        end

        #
        # An OASIS printed id carries the publisher token, and pubid rejects a
        # bare slug — but a caller may well write one ("mqtt-v5.0"), and
        # `Db#fetch` hands the reference through verbatim. Supplying the token
        # is normalization, not identification, so it happens here rather than
        # in the grammar.
        #
        # The token is stripped **case-insensitively** and re-added in its
        # canonical form. pubid's grammar matches the literal `OASIS `, so a
        # lowercase `oasis stix` would otherwise keep its own token, be given a
        # second one, and search for the specification named `oasis stix`.
        # Everything after the token stays verbatim: an OASIS slug is
        # case-sensitive (`STIX`, `amqp-core`, `OpenDocument`).
        #
        # @param text [String]
        # @return [Pubid::Oasis::Identifier, nil]
        #
        def parse_ref(text)
          slug = text.to_s.strip.sub(/\A#{Regexp.escape PREFIX}/i, "")
          ::Pubid::Oasis::Identifier.parse "#{PREFIX}#{slug}"
        rescue StandardError => e
          Util.warn "Failed to parse pubid `#{text}`: #{e.message}"
          nil
        end

        #
        # Ignore exactly what the reference left out (the ETSI/W3C/OGC idiom),
        # so `OASIS STIX` reaches every STIX row while
        # `OASIS STIX-v2.1-CS02` reaches only its own. `number` — the
        # specification name — is never ignorable: it is the whole identity of
        # an OASIS record and the key the index bsearches on.
        #
        # @param pubid [Pubid::Oasis::Identifier]
        # @return [Array<Symbol>]
        #
        def ignored(pubid)
          OPTIONAL.select { |attr| pubid.public_send(attr).nil? }
        end

        #
        # Order the matched rows. Ignoring a component means "don't care", so a
        # loose reference matches the more specific rows too and this key
        # decides between them:
        #
        # 1. an **exact printed id** always wins. Five published records are a
        #    bare specification name that also has versioned siblings — `OASIS
        #    EDXL`, `OData`, `OSLC`, `SAML`, `WSS` — and each is a real
        #    document in its own right. Without this key the "newest version"
        #    rule below answers a request for the bare record with its newest
        #    sibling; three of the five did exactly that. Published ids are
        #    unique (0 duplicates in 605 rows), so at most one row scores here;
        # 2. then the **newest version**, segments compared as integers —
        #    `v2.1` beats `v1.2.1`, and `v10` beats `v9`, which a string
        #    compare gets wrong;
        # 3. then the **least specific** row, i.e. the fewest components the
        #    reference did not ask for — a bare `OASIS STIX` wants `STIX-v2.1`,
        #    not `STIX-v2.1-CS02`, and `OASIS STIX-v1.2.1-CS01` wants that
        #    record itself, not its `-Pt3-Core` part;
        # 4. then the **later stage revision** (`CS02` over `CS01`). Only the
        #    digits are compared: OASIS stage letters have no ranking this code
        #    is entitled to invent;
        # 5. then the printed id, so the result never depends on index order.
        #
        # Checked against every published row: all 605 resolve to their own
        # record, with and without the publisher token.
        #
        # @param pubid [Pubid::Oasis::Identifier] the parsed reference
        # @param id [Pubid::Oasis::Identifier] a matched row's id
        # @return [Array]
        #
        def ranking_key(pubid, id)
          exact = id.to_s == pubid.to_s ? 1 : 0
          extra = ignored(pubid).count { |attr| id.public_send(attr) }
          [exact, digits(id.version), -extra, digits(id.stage), id.to_s]
        end

        # Integer segments of a version or stage token, for numeric ordering
        # ("v1.2.1" -> [1, 2, 1], "CS02" -> [2], nil -> []).
        #
        # @param token [String, nil]
        # @return [Array<Integer>]
        def digits(token)
          token.to_s.scan(/\d+/).map(&:to_i)
        end

        def fetch_yaml(uri)
          resp = Net::HTTP.get_response uri
          unless resp.code == "200"
            raise Relaton::RequestError,
                  "Could not access #{uri}: HTTP #{resp.code}"
          end
          resp.body
        end

        def parse_item(yaml, text)
          item = Item.from_yaml yaml
          Util.info "Found: `#{item.docidentifier.first.content}`", key: text
          item.tap { |i| i.fetched = Date.today.to_s }
        end
      end
    end
  end
end
