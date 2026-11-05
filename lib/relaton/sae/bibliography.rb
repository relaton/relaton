require "net/http"

module Relaton
  module Sae
    module Bibliography
      # Transport failures of the document fetch. They become
      # `Relaton::RequestError`, the one class `Relaton::Db#net_retry` retries.
      NET_ERRORS = [
        SocketError, Errno::EINVAL, Errno::ECONNRESET, Errno::ECONNREFUSED,
        Errno::ETIMEDOUT, EOFError, Net::HTTPBadResponse,
        Net::HTTPHeaderSyntaxError, Net::ProtocolError, Net::OpenTimeout,
        Net::ReadTimeout, OpenSSL::SSL::SSLError
      ].freeze

      class << self
        #
        # Fetch an SAE standard.
        #
        # @param ref [String, Pubid::Sae::Identifier] `SAE J3016`,
        #   `SAE J3016:2021`, or SAE's native edition code `SAE J3016_202104`
        # @param year [String, nil]
        # @param _opts [Hash]
        # @return [Relaton::Sae::ItemData, nil]
        #
        def get(ref, year = nil, _opts = {})
          Util.info "Fetching from Relaton repository ...", key: ref.to_s
          pubid = parse_ref ref, year
          return not_found(ref) unless pubid

          row = best_match pubid
          item = row && fetch_doc(row[:file])
          return not_found(ref) unless item

          Util.info "Found: `#{primary_id item}`", key: ref.to_s
          item
        end

        private

        def not_found(ref)
          Util.info "Not found.", key: ref.to_s
          nil
        end

        #
        # The query as a `Pubid::Sae::Identifier`.
        #
        # A parsed pubid comes from `Relaton::Db` (relaton#205): it is not
        # mutated, so a year argument goes on a copy. A reference pubid cannot
        # read answers nil, so `get` answers not-found with a log line instead
        # of raising (relaton#235): `Db` passes such a reference as a String.
        #
        # @return [Pubid::Sae::Identifier, nil]
        #
        def parse_ref(ref, year)
          ref = parse_text(ref.to_s.strip) unless ref.is_a?(::Pubid::Sae::Identifier)
          return ref unless ref && year

          copy = ::Pubid::Sae::Identifier.from_hash ref.to_hash
          copy.date = ::Pubid::Sae::Components::Date.new(year: year.to_i)
          copy
        end

        def parse_text(text)
          ::Pubid::Sae::Identifier.parse text
        rescue ::Pubid::Errors::Error, ArgumentError => e
          Util.info "Not an SAE identifier pubid reads: #{e.message}", key: text
          nil
        end

        #
        # The index row for a query: the newest edition among its matches.
        #
        # Passing the pubid (not a String) is what makes `Index::Type#search`
        # narrow to the `number` bucket, and with no block it selects with
        # pubid's subset match `query === row`: a revision, a year or a month
        # the query omits matches any value, and the type (`J`, `AMS`, …), a
        # part and an amendment must agree.
        #
        # Of the matches, the highest revision wins (aerospace standards), then
        # the latest date (J-series editions). `r[:file]` breaks a tie, because
        # the index sort is not stable.
        #
        # @param pubid [Pubid::Sae::Identifier]
        # @return [Hash, nil]
        #
        def best_match(pubid)
          index.search(pubid).max_by do |r|
            id = r[:id]
            [revision_rank(id.revision), id.year.to_i, id.date&.month.to_i,
             r[:file]]
          end
        end

        # `B` follows `A`, and a two-letter revision (`AA`) follows `Z`.
        def revision_rank(revision)
          [revision.to_s.size, revision.to_s]
        end

        # @param file [String] the row's path in the data repo
        # @return [Relaton::Sae::ItemData, nil] nil when the file is missing
        def fetch_doc(file)
          uri = URI("#{ENDPOINT}#{file}")
          resp = Net::HTTP.get_response uri
          return if resp.code == "404"
          unless resp.code == "200"
            raise Relaton::RequestError,
                  "Could not access #{uri}: HTTP #{resp.code}"
          end

          Item.from_yaml(resp.body).tap { |i| i.fetched = Date.today.to_s }
        rescue *NET_ERRORS => e
          raise Relaton::RequestError, "Could not access #{uri}: #{e.message}"
        end

        def primary_id(item)
          (item.docidentifier.detect(&:primary) || item.docidentifier.first)&.content
        end

        def index
          Relaton::Index.find_or_create(
            :sae, pages_url: PAGES_URL, pubid_class: ::Pubid::Sae::Identifier
          )
        end
      end
    end
  end
end
