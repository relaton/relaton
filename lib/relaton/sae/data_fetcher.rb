require "net/http"
require "relaton/core"
require "relaton/json"
require_relative "../sae"
require_relative "../doi"

module Relaton
  module Sae
    #
    # Crawl every SAE standard from Crossref into a data repo.
    #
    # sae.org answers a script with a CAPTCHA, and Crossref's text search does
    # not find a standard by its identifier, but SAE deposits each edition
    # with a DOI under prefix `10.4271` and type `standard`. This walks that
    # set with Crossref's deep-paging cursor (1000 records a request, about 48
    # requests), maps each record with `Relaton::Doi::Parser`, and writes one
    # document per edition and the pubid `index-v2`.
    #
    class DataFetcher < Core::DataFetcher
      SOURCES = %w[sae-crossref].freeze
      URL = "https://api.crossref.org/prefixes/10.4271/works".freeze
      ROWS = 1000
      # Crossref's public pool allows far more; one request a second is polite
      # and still finishes the crawl in about a minute of waits.
      GAP = 1
      # Attempts for one page before the crawl gives up.
      ATTEMPTS = 5
      RETRY_CODES = %w[429 500 502 503 504].freeze

      def fetch(source = nil)
        unless SOURCES.include? source
          raise ArgumentError,
                "Unknown source `#{source}`, expected one of #{SOURCES}"
        end

        @newest = {}
        each_page { |items| items.each { |work| parse_work work } }
        index.save
        report_errors
      end

      def index
        # `pubid_class:` on the producer too: FileIO#save calls `to_hash` only
        # for instances of it, so without it the crawl writes v1-shaped rows
        # under a v2 name.
        @index ||= Relaton::Index.find_or_create(
          :sae, file: "#{INDEXFILE}.yaml", pubid_class: ::Pubid::Sae::Identifier
        )
      end

      def log_error(msg)
        Util.error msg
      end

      private

      def each_page
        cursor = "*"
        loop do
          message = get_page(cursor)
          items = message["items"]
          break if items.nil? || items.empty?

          yield items
          cursor = message["next-cursor"]
          break unless cursor
        end
      end

      #
      # One page of the cursor walk. A throttle or a server error is retried
      # with a growing wait; anything else, or a page that keeps failing,
      # stops the crawl, because a partial crawl would publish a partial index.
      #
      # @param cursor [String]
      # @return [Hash] the `message` of the response
      #
      def get_page(cursor) # rubocop:disable Metrics/MethodLength
        uri = page_uri cursor
        ATTEMPTS.times do |n|
          pacer.wait
          resp, failure = attempt uri
          return Relaton::Json.parse_external(resp.body)["message"] if resp&.code == "200"
          if resp && !RETRY_CODES.include?(resp.code)
            raise Relaton::RequestError, "Crossref HTTP #{resp.code} for #{uri}"
          end

          break if n == ATTEMPTS - 1

          Util.warn "Crossref #{failure || "HTTP #{resp.code}"}, " \
                    "retry #{n + 1} of #{ATTEMPTS - 1}"
          sleep backoff(resp, n + 1)
        end
        raise Relaton::RequestError,
              "Crossref keeps failing for #{uri} after #{ATTEMPTS} attempts"
      end

      # A transport error is retried like a 5xx: one timeout in ~48 requests
      # must not fail the crawl.
      #
      # @return [Array(Net::HTTPResponse|nil, String|nil)] the response, or nil
      #   and the error message
      def attempt(uri)
        [http_get(uri), nil]
      rescue *Bibliography::NET_ERRORS => e
        [nil, "#{e.class}: #{e.message}"]
      end

      def page_uri(cursor)
        uri = URI URL
        uri.query = URI.encode_www_form(filter: "type:standard", rows: ROWS,
                                        cursor: cursor)
        uri
      end

      def http_get(uri)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                            open_timeout: 30, read_timeout: 120) do |http|
          http.get uri.request_uri, "User-Agent" => Relaton::Doi::Crossref::USER_AGENT
        end
      end

      # Crossref sends `X-Rate-Limit-Interval: 1s`; a throttled response can
      # carry no such header, so the wait is never less than a second.
      def backoff(resp, num)
        interval = resp&.[]("x-rate-limit-interval").to_s[/\d+/].to_i
        [interval, 1].max * num * 2
      end

      def pacer
        @pacer ||= Core::Pacer.new(gap: GAP)
      end

      #
      # Write one Crossref record and index it.
      #
      # @param work [Hash] a Crossref work
      #
      def parse_work(work)
        code = DoiCode.parse work["DOI"], approved_year: approved_year(work)
        return Util.warn("Not an SAE DOI: `#{work['DOI']}`") unless code

        item = to_item work, code
        file = write_unique code.native, serialize(item)
        add_to_index code, work, file
      end

      def approved_year(work)
        (work["approved"] || work["issued"])&.dig("date-parts", 0, 0)
      end

      #
      # The `Relaton::Doi::Parser` item, with SAE's edition code (as SAE
      # prints it) as its primary identifier and the DOI kept beside it.
      #
      # @return [Relaton::Sae::ItemData]
      #
      def to_item(work, code)
        bib = Relaton::Doi::Parser.parse work
        bib.id = code.native.delete(" /").gsub(/\W/, "")
        bib.docidentifier = [
          Bib::Docidentifier.new(type: "SAE", content: code.printed,
                                 primary: true),
          *bib.docidentifier.map do |d|
            Bib::Docidentifier.new(type: d.type, content: d.content)
          end,
        ]
        bib.ext = Bib::Ext.new(doctype: Bib::Doctype.new(content: "standard"),
                               flavor: "sae")
        Item.from_yaml Bib::Item.to_yaml(bib)
      end

      #
      # Index the edition under its pubid, or record why it cannot be.
      #
      # An id pubid cannot read is recorded in `@errors` (the inherited
      # `report_errors` logs it and opens the crawl's GitHub issue) and the row
      # is skipped: `Relaton::Index` rejects the WHOLE index when one row fails
      # to deserialize. The data file is already written, so the document is
      # unindexed, never lost.
      #
      # The key carries the month, so two editions of one year are two rows.
      # Two DOIs that spell one code (`ams-4121j`, `ams4121j`) share a key;
      # the one with the later DOI date, then approval date, keeps the row.
      #
      def add_to_index(code, work, file)
        pubid = parse_pubid code
        unless pubid
          @errors[code.native] =
            "Unparseable SAE id `#{code.native}` was not indexed (#{file})"
          return
        end

        key = pubid.to_s
        stamp = [code.date.to_s, approved_stamp(work)]
        return if @newest[key] && (@newest[key] <=> stamp) >= 0

        @newest[key] = stamp
        index.add_or_update pubid, file
      end

      def parse_pubid(code)
        ::Pubid::Sae::Identifier.parse code.reference
      rescue ::Pubid::Errors::Error, ArgumentError
        nil
      end

      def approved_stamp(work)
        Array(work.dig("approved", "date-parts", 0)).map do |d|
          d.to_i.to_s.rjust(2, "0")
        end.join("-")
      end

      def to_yaml(bib) = bib.to_yaml
      def to_xml(bib) = Bibdata.to_xml(bib)
      def to_bibxml(bib) = bib.to_rfcxml
    end
  end
end
