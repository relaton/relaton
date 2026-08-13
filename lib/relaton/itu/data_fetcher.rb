require "net/http"
require "json"
require "uri"
require "mechanize"
require_relative "../itu"
require_relative "data_parser_t"

module Relaton
  module Itu
    class DataFetcher < Core::DataFetcher
      # ITU-T recommendation index (issue relaton-itu#80). main_edition_flag=0
      # returns one row per edition, including supplements; a single request
      # enumerates the whole ITU-T corpus.
      SEARCH_RECS_URL = "https://www.itu.int/mws/api/recommendations/searchRecs".freeze
      # A browser User-Agent — www.itu.int sits behind an F5 WAF that rejects
      # non-browser clients (it is what killed the old RunSearch endpoint), so
      # Net::HTTP's default "Ruby" UA must not be sent.
      USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " \
                   "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Safari/605.1.15".freeze
      DEFAULT_CONCURRENCY = 8

      # Why there is no ITU-R harvester. The crawler used to page
      # `POST net4/ITU-T/search/GlobalSearch/RunSearch` with `Input: "*"`, which
      # returned enumeration *and* full metadata in one shot; ITU decommissioned
      # it (the endpoint now answers HTTP 500 with the search SPA's HTML shell,
      # so the old path died on a `JSON::ParserError` that named neither the
      # endpoint nor the cause). Say so instead.
      ITU_R_DISABLED = <<~MSG.freeze
        ITU-R harvesting is disabled: ITU decommissioned the RunSearch bulk-enumeration
        endpoint (POST https://www.itu.int/net4/ITU-T/search/GlobalSearch/RunSearch) that
        this crawler paged through, and no replacement enumeration source is wired up.
        Published ITU-R records are preserved in relaton-data-itu and re-indexed by
        DataFetcher#index_files. See https://github.com/relaton/relaton/issues/75
      MSG

      # Number of ITU-T enrichment worker threads. Each record costs ~4
      # www.itu.int round-trips (~3.7 s wall clock), so a ~16k-record corpus is
      # ~17 h single-threaded — past the 6 h GitHub Actions job cap. The work is
      # pure I/O wait, so a small pool is close to linear. Tunable via env var so
      # a run can dial it down when the F5 WAF in front of www.itu.int starts
      # throttling (or up to 1 to reproduce the serial order). Never below 1.
      def self.concurrency
        [(ENV["RELATON_ITU_CONCURRENCY"] || DEFAULT_CONCURRENCY).to_i, 1].max
      end

      def initialize(output, format)
        super
        # Guards the shared bookkeeping (@files, @seen, @errors, @unparseable_ids,
        # @enrichment_failures) and the index mutation while workers fetch detail
        # pages in parallel. The slow HTTP runs outside this lock; only the cheap
        # build+write is held.
        @mutex = Mutex.new
        # output file => searchRecs position of the row that claimed it, so a
        # duplicate filename resolves to the same last-by-position winner the
        # serial crawl picked, regardless of worker completion order.
        @seen = {}
        @done = 0
        @enrichment_failures = 0
      end

      def index
        @index ||= Relaton::Index.find_or_create(
          :itu, file: "#{INDEXFILE}.yaml", pubid_class: ::Pubid::Itu::Identifier
        )
      end

      def log_error(msg)
        Util.error msg
      end

      # @param source [String, nil] "itu-t" harvests ITU-T recommendations via
      #   the searchRecs index (issue #80). "itu-r" (and nil, the legacy default)
      #   has no harvester any more — see ITU_R_DISABLED and issue #75; the
      #   published ITU-R records are preserved and re-indexed by #index_files.
      # @raise [Relaton::RequestError] for any source but "itu-t"
      def fetch(source = nil)
        raise Relaton::RequestError, ITU_R_DISABLED unless source == "itu-t"

        fetch_recommendations
        index.save
        report_errors
      end

      # ITU-T harvester: one searchRecs request enumerates every edition and
      # supplement; each row is then enriched with getRecHdrDetail-sourced fields
      # (abstract, ISO co-id, editorial-group contributors, status), so harvested
      # records match the live runtime output. Enrichment is ~4 requests per
      # record — the bulk of the crawl's cost — so the rows are spread over a
      # worker pool (see .concurrency) and progress is logged.
      #
      # Each worker owns its own Mechanize agent: Mechanize is not thread-safe,
      # and per-worker agents also keep one worker's cookie/history state out of
      # another's. Rows carry their searchRecs position so #write_file can pick a
      # deterministic winner for duplicate filenames.
      def fetch_recommendations
        rows = search_recs
        n = self.class.concurrency
        agents = Array.new(n) { rec_agent }
        queue = SizedQueue.new(n * 2)
        workers = agents.map { |agent| spawn_rec_worker(queue, agent, rows.size) }
        rows.each_with_index { |row, pos| queue << [row, pos] }
        n.times { queue << nil } # poison pills
        workers.each(&:join)
        report_enrichment_failures rows.size
      ensure
        agents&.each(&:shutdown)
      end

      # One pool worker: drains the queue with its own agent until the poison
      # pill (nil). Per-row errors are logged and skipped, so one bad row never
      # kills a worker and leaves the queue undrained.
      def spawn_rec_worker(queue, agent, total)
        Thread.new do
          while (item = queue.pop)
            row, pos = item
            begin
              errors = Hash.new(true)
              bib = DataParserT.parse(row, agent, errors)
              if bib
                # DataParserT#enrichment adds the ITU publisher unconditionally
                # when it succeeds, so an empty contributor list is exactly the
                # set of records whose detail fetch failed and degraded to the
                # thin searchRecs shape.
                count_enrichment_failure if bib.contributor.empty?
                write_file bib, pos
              end
              merge_errors errors
            rescue => e # rubocop:disable Style/RescueStandardError
              Util.error "#{e.message}\n#{e.backtrace}"
            end
            progress total
          end
        end
      end

      # Each parse gets its own errors hash (DataParserT is per-call state, but
      # the flags are AND-folded across all rows), merged back under the lock.
      def merge_errors(errors)
        @mutex.synchronize { errors.each { |k, v| @errors[k] &&= v } }
      end

      def progress(total)
        done = @mutex.synchronize { @done += 1 }
        Util.info "ITU-T: enriched #{done}/#{total}" if (done % 500).zero?
      end

      def count_enrichment_failure
        @mutex.synchronize { @enrichment_failures += 1 }
      end

      # Enrichment is best-effort: a failed detail fetch degrades that record to
      # the thin searchRecs shape instead of losing it, and the crawl runs to
      # completion either way. That is right for one flaky record and dangerous
      # in bulk — a WAF block would quietly republish a metadata-thin corpus — so
      # say how many records lost their enrichment.
      def report_enrichment_failures(total)
        return if @enrichment_failures.zero?

        Util.warn "ITU-T: enrichment failed for #{@enrichment_failures}/#{total} records"
      end

      # Mechanize agent for per-record enrichment. A browser User-Agent is
      # required — www.itu.int sits behind the F5 WAF that rejects non-browser
      # clients (mirrors HitCollection#agent).
      #
      # max_history: Mechanize retains every response it fetches, unbounded by
      #   default. Enrichment issues ~4 requests per record and one of them is
      #   the ~90 KB rec.aspx page that #fetch_workgroup parses into a DOM; over
      #   a 16k-record corpus (times one agent per worker) that history grows
      #   into the gigabytes.
      # timeouts: Mechanize sets none, so a single stalled www.itu.int socket
      #   would park a worker indefinitely with no error and no progress. A
      #   timeout raises Net::{Open,Read}Timeout < Timeout::Error, which
      #   RecommendationFields#request_document already turns into a
      #   Relaton::RequestError and DataParserT#enrichment rescues — so it costs
      #   one thin record rather than the run.
      def rec_agent
        Mechanize.new.tap do |a|
          a.user_agent_alias = "Mac Safari"
          a.max_history = 1
          a.open_timeout = 15
          a.read_timeout = 60
        end
      end

      # @param bib [Relaton::Itu::ItemData]
      # @param pos [Integer, nil] source position of the row this came from, used
      #   only to break filename collisions deterministically (nil for the
      #   single-threaded ITU-R path)
      def write_file(bib, pos = nil) # rubocop:disable Metrics/AbcSize
        id = bib.docidentifier.find(&:primary).content
        file = output_file(id)
        content = serialize(bib) # outside the lock: it is the expensive part
        @mutex.synchronize do
          if @files.include? file
            Util.warn "File #{file} exists."
            # Distinct docids can sanitize to one filename, in which case the
            # serial crawl left the last row's version on disk. Keep that
            # outcome whatever order the workers finish in.
            return if pos && @seen[file] && @seen[file] > pos
          else
            @files << file
          end
          @seen[file] = pos
          index_primary(id, file)
          File.write file, content, encoding: "UTF-8"
        end
      end

      # Index records that are already on disk instead of harvesting them.
      #
      # ITU-R cannot be re-harvested — ITU decommissioned the bulk RunSearch
      # enumeration, which is why #fetch now refuses the "itu-r" source
      # (ITU_R_DISABLED, issue #75) — so the
      # published ITU-R records are preserved and only re-indexed on each run of
      # relaton-data-itu's crawler. Doing that here rather than in the data repo
      # gives the pass the same pubid guard and the same unparseable-id reporting
      # as the ITU-T harvest, instead of a copy of both living downstream. Drive
      # it and #fetch off one instance so there is a single index, a single
      # unparseable-id list and a single error report:
      #
      #   fetcher = DataFetcher.new("data", "yaml")
      #   fetcher.index_files "data/itu-r-*.yaml"
      #   fetcher.fetch "itu-t"
      #
      # @param glob [String] e.g. "data/itu-r-*.yaml"
      # @return [Integer] number of files indexed
      def index_files(glob)
        indexed = 0
        files = Dir[glob].sort
        files.each do |file|
          item = Item.from_yaml(File.read(file, encoding: "UTF-8"))
          id = (item.docidentifier.find(&:primary) || item.docidentifier.first)&.content
          if id
            indexed += 1 if index_primary(id, file)
          else
            unparseable_ids << ["(no docidentifier)", file]
          end
        rescue => e # rubocop:disable Style/RescueStandardError
          Util.error "Failed to index #{file}: #{e.message}"
        end
        Util.info "ITU: indexed #{indexed}/#{files.size} existing records from #{glob}"
        indexed
      end

      # Index the id's parsed pubid. If it can't be parsed/round-tripped, record
      # it so #report_errors raises a tracked GitHub issue; the data file is
      # still written, so the document is not lost — only unindexed until its id
      # parses (mirrors Relaton::Iso::DataFetcher#index_primary).
      #
      # @param id [String] primary docidentifier content, e.g. "ITU-R BO.600-1"
      # @param file [String] file name of the document
      # @return [Boolean] whether the id was indexed
      def index_primary(id, file)
        if (pid = pubid(id))
          index.add_or_update pid, file
          true
        else
          unparseable_ids << [id, file]
          false
        end
      end

      def unparseable_ids
        @unparseable_ids ||= []
      end

      # Surface unparseable ids through the shared error machinery (the
      # "Error fetching documents" GitHub issue in CI). The gh_issue channel is
      # registered inside #gh_issue, so log at :error after it is set up and
      # before super creates the issue (mirrors
      # Relaton::Iso::DataFetcher#report_errors).
      def report_errors
        gh_issue
        unparseable_ids.each do |content, file|
          log_error "Unparseable primary id `#{content}` was not indexed (#{file})"
        end
        super
      end

      # Parse an ITU docid into a Pubid::Itu identifier, or nil when it can't be
      # parsed or does not round-trip losslessly. Storing the pubid object (not
      # its hash) lets Relaton::Index sort the index and serialize each id to its
      # `_type: pubid:itu:*` hash on save. The round-trip check mirrors the index
      # loader's own Index::FileIO#id_supported? acceptance test, so an id that
      # would make Relaton::Index reject the whole index is dropped at write time.
      # The pinned pubid models recommendations, handbooks and questions, so the
      # guard only skips the few residual forms it can't parse (e.g. "ITU-R RR").
      #
      # @param id [String]
      # @return [::Pubid::Itu::Identifier, nil]
      def pubid(id)
        pid = ::Pubid::Itu.parse id
        hash = pid.to_hash
        return nil unless ::Pubid::Itu::Identifier.from_hash(hash).to_hash == hash

        pid
      rescue StandardError
        nil
      end

      def to_yaml(bib)
        bib.to_yaml
      end

      def to_xml(bib)
        bib.to_xml bibdata: true
      end

      def to_bibxml(bib)
        bib.to_rfcxml
      end

      private

      # Fetch the full ITU-T recommendation index in one request.
      # @return [Array<Hash>] rows from the searchRecs "Data" array
      def search_recs
        uri = URI(SEARCH_RECS_URL)
        uri.query = URI.encode_www_form(
          series: -1, type_of_text: -1, sg: -1, main_edition_flag: 0,
          rows: 100_000, page: 1, status: "Z", sort_order: "asc"
        )

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/json"
        request["Referer"] = "https://www.itu.int/myworkspace/"
        request["User-Agent"] = USER_AGENT

        response = http.request(request)
        json = JSON.parse(response.body)
        json["Data"] || []
      end
    end
  end
end
