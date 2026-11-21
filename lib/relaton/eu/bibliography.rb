require "net/http"

module Relaton
  module Eu
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
        # Fetch an EU legal act.
        #
        # @param ref [String, Pubid::Eu::Identifier] `EU Regulation 1227/2011`
        # @param year [String, nil] the act's year; a reference always states
        #   it, so a year that differs finds nothing
        # @param _opts [Hash]
        # @return [Relaton::Bib::ItemData, nil]
        #
        def get(ref, year = nil, _opts = {})
          Util.info "Fetching from Relaton repository ...", key: ref.to_s
          pubid = parse_ref ref
          return not_found(ref) unless pubid && (year.nil? || year.to_s == pubid.year.to_s)

          row = select_row index.search(pubid), pubid
          item = row && fetch_doc(row[:file])
          return not_found(ref) unless item

          Util.info "Found: `#{item.docidentifier.first.content}`", key: ref.to_s
          item
        end

        private

        #
        # Before 2015 a decision had two number series, so two acts can share
        # a number and a year: Council Decision No 252/2013/EU and Commission
        # Implementing Decision 2013/252/EU. `===` ignores the print order,
        # so both rows match; the row printed in the query's order wins.
        # `number_first?` is the order pubid prints: the stored flag is nil
        # for the default order, and a caller can set the default explicitly.
        # With no such row (a query in the other order), the first file.
        #
        def select_row(rows, pubid)
          rows.find { |r| r[:id].number_first? == pubid.number_first? } ||
            rows.min_by { |r| r[:file] }
        end

        def not_found(ref)
          Util.info "Not found.", key: ref.to_s
          nil
        end

        #
        # The query as a `Pubid::Eu::Identifier`. A parsed pubid comes from
        # `Relaton::Db` (relaton#205). A reference pubid cannot read answers
        # nil, so `get` answers not-found with a log line (relaton#235).
        #
        # @return [Pubid::Eu::Identifier, nil]
        #
        def parse_ref(ref)
          return ref if ref.is_a?(::Pubid::Eu::Identifier)

          ::Pubid::Eu::Identifier.parse ref.to_s.strip
        rescue ::Pubid::Errors::Error, ArgumentError => e
          Util.info "Not an EU act identifier pubid reads: #{e.message}", key: ref.to_s
          nil
        end

        # @param file [String] the row's path in the data repo
        # @return [Relaton::Bib::ItemData, nil] nil when the file is missing
        def fetch_doc(file)
          uri = URI("#{ENDPOINT}#{file}")
          resp = Net::HTTP.get_response uri
          return if resp.code == "404"
          unless resp.code == "200"
            raise Relaton::RequestError, "Could not access #{uri}: HTTP #{resp.code}"
          end

          Bib::Item.from_yaml(resp.body).tap { |i| i.fetched = Date.today.to_s }
        rescue *NET_ERRORS => e
          raise Relaton::RequestError, "Could not access #{uri}: #{e.message}"
        end

        #
        # `Index::Type#search` with a pubid narrows to the `number` bucket and
        # selects with pubid's subset match `query === row`: the type and the
        # year must agree, and the legal family is a wildcard.
        #
        def index
          Relaton::Index.find_or_create(
            :eu, pages_url: PAGES_URL, pubid_class: ::Pubid::Eu::Identifier
          )
        end
      end
    end
  end
end
