require "net/http"
require_relative "../core"
require_relative "../json"

module Relaton
  module Eu
    #
    # The EU Publications Office CELLAR SPARQL endpoint, for the crawler.
    #
    # One page is one year of sector-3 regulations, directives and decisions
    # (CELEX types R, L and D), one row a work, ordered by CELEX. A field with
    # many values (entry-into-force dates, authors, repealed and amended
    # acts) is one `GROUP_CONCAT` string.
    #
    # A property name with a hyphen is written as a full IRI. The endpoint
    # (Virtuoso) misreads `cdm:resource_legal_date_entry-into-force` as a
    # prefixed name: it answers, but with values from no such property.
    #
    class Cellar
      URL = "https://publications.europa.eu/webapi/rdf/sparql".freeze
      # Rows a request. A year has at most about 7,000 works, and a page of
      # 1,000 answers in about two seconds.
      ROWS = 1000
      # One request at a time, one a second: the endpoint is public.
      GAP = 1
      ATTEMPTS = 5
      RETRY_CODES = %w[429 500 502 503 504].freeze
      NET_ERRORS = [
        SocketError, Errno::EINVAL, Errno::ECONNRESET, Errno::ECONNREFUSED,
        Errno::ETIMEDOUT, EOFError, Net::HTTPBadResponse,
        Net::HTTPHeaderSyntaxError, Net::ProtocolError, Net::OpenTimeout,
        Net::ReadTimeout, OpenSSL::SSL::SSLError
      ].freeze

      # `%<year>s`, `%<limit>d` and `%<offset>d` are filled per page.
      QUERY = <<~SPARQL.freeze
        PREFIX cdm: <http://publications.europa.eu/ontology/cdm#>
        PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
        PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
        SELECT ?celex
          (SAMPLE(?eli_) AS ?eli)
          (SAMPLE(?date_) AS ?date)
          (GROUP_CONCAT(DISTINCT STR(?force_); separator=" ") AS ?force)
          (SAMPLE(?inforce_) AS ?inforce)
          (SAMPLE(?title_) AS ?title)
          (GROUP_CONCAT(DISTINCT CONCAT(STR(?author_), "|", COALESCE(STR(?alabel), "")); separator="\\n") AS ?authors)
          (GROUP_CONCAT(DISTINCT ?repeals_; separator=" ") AS ?repeals)
          (GROUP_CONCAT(DISTINCT ?amends_; separator=" ") AS ?amends)
        WHERE {
          ?w cdm:resource_legal_id_sector "3"^^xsd:string ;
             cdm:resource_legal_year "%<year>s"^^xsd:gYear ;
             cdm:resource_legal_type ?t ;
             cdm:resource_legal_id_celex ?celex .
          FILTER(?t IN ("R"^^xsd:string, "L"^^xsd:string, "D"^^xsd:string))
          OPTIONAL { ?w cdm:resource_legal_eli ?eli_ }
          OPTIONAL { ?w cdm:work_date_document ?date_ }
          OPTIONAL { ?w <http://publications.europa.eu/ontology/cdm#resource_legal_date_entry-into-force> ?force_ }
          OPTIONAL { ?w <http://publications.europa.eu/ontology/cdm#resource_legal_in-force> ?inforce_ }
          OPTIONAL { ?w cdm:work_created_by_agent ?author_ .
                     OPTIONAL { ?author_ skos:prefLabel ?alabel FILTER(LANG(?alabel) = "en") } }
          OPTIONAL { ?w cdm:resource_legal_repeals_resource_legal/cdm:resource_legal_id_celex ?repeals_ }
          OPTIONAL { ?w cdm:resource_legal_amends_resource_legal/cdm:resource_legal_id_celex ?amends_ }
          OPTIONAL { ?e cdm:expression_belongs_to_work ?w ;
                        cdm:expression_uses_language <http://publications.europa.eu/resource/authority/language/ENG> ;
                        cdm:expression_title ?title_ }
        }
        GROUP BY ?celex
        ORDER BY ?celex
        LIMIT %<limit>d OFFSET %<offset>d
      SPARQL

      # The works of one year, for #each_row to check that it read them all.
      COUNT_QUERY = <<~SPARQL.freeze
        PREFIX cdm: <http://publications.europa.eu/ontology/cdm#>
        PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
        SELECT (COUNT(DISTINCT ?celex) AS ?n) WHERE {
          ?w cdm:resource_legal_id_sector "3"^^xsd:string ;
             cdm:resource_legal_year "%<year>s"^^xsd:gYear ;
             cdm:resource_legal_type ?t ;
             cdm:resource_legal_id_celex ?celex .
          FILTER(?t IN ("R"^^xsd:string, "L"^^xsd:string, "D"^^xsd:string))
        }
      SPARQL

      #
      # Each row of one year, page by page.
      #
      # A page shorter than ROWS ends the year. Virtuoso can answer a page
      # short with HTTP 200 (a query timeout, a server row cap), so the year
      # is checked against a COUNT of its works first: a year that read fewer
      # rows raises `Relaton::RequestError` instead of publishing an index
      # without them.
      #
      # @param year [Integer]
      # @yieldparam binding [Hash{String=>Hash}] one SPARQL result row
      #
      def each_row(year, &block)
        expected = count(year)
        read = 0
        offset = 0
        loop do
          rows = page(year, offset)
          rows.each(&block)
          read += rows.size
          break if rows.size < ROWS

          offset += ROWS
        end
        return if read == expected

        raise Relaton::RequestError,
              "CELLAR gave #{read} of #{expected} works for year #{year}"
      end

      # @return [Integer] the works of one year
      def count(year)
        rows = request format(COUNT_QUERY, year: year), "year #{year} count"
        rows.dig(0, "n", "value").to_i
      end

      # @return [Array<Hash>] the result bindings of one page
      def page(year, offset)
        query = format(QUERY, year: year, limit: ROWS, offset: offset)
        request query, "year #{year} offset #{offset}"
      end

      #
      # One request. A throttle, a server error or a transport error is
      # retried with a growing wait; any other answer, an answer Virtuoso
      # marks incomplete, or a request that keeps failing, raises
      # `Relaton::RequestError`: a partial crawl would publish a partial
      # index.
      #
      # @return [Array<Hash>] the result bindings
      #
      def request(query, what) # rubocop:disable Metrics/MethodLength
        uri = query_uri(query)
        ATTEMPTS.times do |n|
          pacer.wait
          resp, failure = attempt uri
          return bindings(resp, what) if resp&.code == "200"
          if resp && !RETRY_CODES.include?(resp.code)
            raise Relaton::RequestError, "CELLAR HTTP #{resp.code} for #{what}"
          end

          break if n == ATTEMPTS - 1

          Util.warn "CELLAR #{failure || "HTTP #{resp.code}"}, " \
                    "retry #{n + 1} of #{ATTEMPTS - 1}"
          sleep 2 * (n + 1)
        end
        raise Relaton::RequestError,
              "CELLAR keeps failing for #{what} after #{ATTEMPTS} attempts"
      end

      private

      # Virtuoso sends `X-SQL-State` with a 200 when it cut the answer
      # short (an anytime query that hit its timeout).
      def bindings(resp, what)
        if resp["x-sql-state"]
          raise Relaton::RequestError,
                "CELLAR answer incomplete for #{what}: " \
                "#{resp['x-sql-state']} #{resp['x-sql-message']}".strip
        end

        Relaton::Json.parse_external(resp.body).dig("results", "bindings") || []
      end

      def attempt(uri)
        [http_get(uri), nil]
      rescue *NET_ERRORS => e
        [nil, "#{e.class}: #{e.message}"]
      end

      def query_uri(query)
        uri = URI URL
        uri.query = URI.encode_www_form(query: query)
        uri
      end

      def http_get(uri)
        Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                            open_timeout: 30, read_timeout: 180) do |http|
          http.get uri.request_uri, "Accept" => "application/sparql-results+json"
        end
      end

      def pacer
        @pacer ||= Core::Pacer.new(gap: GAP)
      end
    end
  end
end
