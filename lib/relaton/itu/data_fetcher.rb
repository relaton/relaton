require "net/http"
require "json"
require "uri"
require "mechanize"
require_relative "../itu"
require_relative "data_parser_t"
require_relative "family_cache"

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

      # ITU-R crawl worker threads. Duplicated from DataCrawlerR::DEFAULT_CONCURRENCY
      # rather than read from it, so this knob does not drag the whole ITU-R
      # harvester into an ITU-T-only crawl — #fetch_publications requires that
      # file lazily and deliberately.
      DEFAULT_R_CONCURRENCY = 4


      # Number of ITU-T enrichment worker threads. Each record costs ~4
      # www.itu.int round-trips (~3.7 s wall clock), so a ~16k-record corpus is
      # ~17 h single-threaded — past the 6 h GitHub Actions job cap. The work is
      # pure I/O wait, so a small pool is close to linear. Tunable via env var so
      # a run can dial it down when the F5 WAF in front of www.itu.int starts
      # throttling (or up to 1 to reproduce the serial order). Never below 1.
      def self.concurrency
        [(ENV["RELATON_ITU_CONCURRENCY"] || DEFAULT_CONCURRENCY).to_i, 1].max
      end

      # Number of ITU-R crawl worker threads. Its own knob, not ITU-T's, because
      # the two halves have different bottlenecks: ITU-T is latency-bound, ITU-R
      # is *pacer*-bound. Throughput there is min(1/delay, concurrency/latency),
      # so at the 1 s default and ITU's ~1.1 s latency two workers already
      # saturate the politeness contract; the default of 4 is headroom for a slow
      # page, not extra load. `RELATON_ITU_R_CONCURRENCY=1` restores a strictly
      # serial crawl.
      def self.r_concurrency
        [(ENV["RELATON_ITU_R_CONCURRENCY"] || DEFAULT_R_CONCURRENCY).to_i, 1].max
      end

      # How RELATON_ITU_DELAY is spent.
      #
      #   slot  (default) it is the minimum gap between request *starts*, shared
      #         by the pool, so ITU's own latency counts toward it instead of
      #         being added on top. www.itu.int sees at most 1/delay req/s no
      #         matter how many workers there are.
      #   fixed sleep it before every request, whatever else is happening. With
      #         RELATON_ITU_R_CONCURRENCY=1 this reproduces the pre-pool crawler
      #         exactly — one request per (delay + latency) — and is the rollback
      #         if ITU ever objects to the new profile.
      def self.pace_mode
        ENV["RELATON_ITU_PACE"].to_s == "fixed" ? :fixed : :slot
      end

      # The ITU-T cross-row cache for a crawl. `RELATON_ITU_CACHE_ENTRIES=0`
      # turns it off entirely, restoring today's exact request pattern.
      def self.family_cache
        entries = ENV["RELATON_ITU_CACHE_ENTRIES"]
        return NullCache.instance if entries.to_s.strip == "0"

        size = entries.to_i
        FamilyCache.new(max_entries: size.positive? ? size : FamilyCache::DEFAULT_MAX_ENTRIES)
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
      #   the searchRecs index (issue #80); "itu-r" (and nil, the legacy default)
      #   harvests ITU-R Recommendations and Reports by crawling ITU's
      #   server-rendered pages (issue #75, see #fetch_publications).
      def fetch(source = nil)
        source == "itu-t" ? fetch_recommendations : fetch_publications
        index.save
        report_errors
      end

      # ITU-R harvester. ITU decommissioned the RunSearch bulk-enumeration
      # endpoint this used to page through, so enumeration walks the `/pub` +
      # `/rec` pages ITU still renders server-side (`DataCrawlerR`).
      #
      # Two modes, because a full crawl is ~7k requests and ~4 h:
      #
      # * **`:full`** (default) — every edition of every document, deep. Pair it
      #   with wiping `data/itu-r-*` first: ITU is then the sole author of the
      #   result, which is the point of crawling it at all.
      # * **`:top_up`** — enumerate the same documents, but deep-fetch only the
      #   editions the dataset does not already hold. Costs the enumeration
      #   (~1 request per document) plus one per genuinely new edition, so a day
      #   with no new publications is a small fraction of a full run.
      #
      # Set with `RELATON_ITU_MODE=top_up`, so the two scheduled jobs differ by
      # environment rather than by code.
      #
      # A top-up assumes the dataset it tops up was built by a previous `:full`
      # run. Against the pre-#110 dataset it would add every Report a second time
      # under its `Report …` name, so the data repo runs the rebuild first and
      # enables the daily job after — an ordering that belongs to the schedule, not
      # to this class. That one wipe retires the old names for good, which is why
      # the harvester carries no migration step.
      #
      # Cost, measured: the BO series of both families is ~230 requests in 484 s
      # at the 1 s default — ~2.1 s per request once ITU's own latency is added.
      # Lower RELATON_ITU_DELAY at your peril: 0.4 s tripped the WAF mid-run
      # (503 on /rec, a 302 to notfound.aspx on /pub), 1 s did not.
      #
      # @param mode [Symbol] :full or :top_up
      # @return [Hash] the merge tally, `collisions` being a count
      def fetch_publications(mode: self.class.mode)
        require_relative "data_crawler_r"
        require_relative "data_merge_r"
        crawler = DataCrawlerR.new delay: self.class.delay,
                                   concurrency: self.class.r_concurrency,
                                   pace_mode: self.class.pace_mode
        stats = Hash.new 0
        DataCrawlerR::FAMILIES.each_key { |family| harvest_family crawler, family, stats, mode }
        Util.info "ITU-R (#{mode}): #{stats.reject { |k, _| k == :collisions }.map { |k, v| "#{k} #{v}" }.join ', '}"
        # Say it out loud: a run that was throttled but recovered otherwise looks
        # identical to a clean one, and a run the governor abandoned would
        # otherwise be visible only as a thin corpus.
        if crawler.throttle_count.positive?
          Util.warn "ITU-R: #{crawler.throttle_count} rate-limit responses from www.itu.int" \
                    "#{'; crawl ABANDONED as rate-limited' if crawler.abandoned?}"
        end
        stats
      ensure
        crawler&.shutdown
      end

      # One family, series by series, so a series that fails — ITU throttles by
      # path family and a blocked series raises — costs that series rather than
      # the whole run.
      #
      # @return [void]
      def harvest_family(crawler, family, stats, mode = :full)
        crawler.series(family).each do |series|
          items = crawler.harvest series, family: family, errors: @errors,
                                          skip: (method(:held?) if mode == :top_up)
          # `collisions` comes back as the offending pairs; the run-level tally
          # keeps their count and leaves the detail to DataMergeR's own errors.
          DataMergeR.write_all(items, self).each { |k, v| stats[k] += v.is_a?(Array) ? v.size : v }
          Util.info "ITU-R #{family}-#{series}: #{items.size} harvested"
        rescue => e # rubocop:disable Style/RescueStandardError
          log_error "ITU-R #{family}-#{series} skipped: #{e.message}"
        end
      rescue => e # rubocop:disable Style/RescueStandardError
        log_error "ITU-R #{family} series index unavailable: #{e.message}"
      end

      # Does the dataset already hold this edition? Answered from the level-2 row
      # alone — the id and displayed code are enough to derive the docid, and so
      # the filename — which is what lets a top-up decide *before* paying for the
      # edition page.
      #
      # @param row [Hash] a level-2 edition row, with :family
      # @return [Boolean]
      def held?(row)
        docid = DataParserR.family_docid row
        docid && File.exist?(output_file(docid))
      end

      # Minimum seconds between ITU-R request *starts*, enforced by one
      # Core::Pacer shared by the whole pool — not a sleep before each request,
      # which would add to ITU's own ~1.1 s latency instead of being absorbed by
      # it. www.itu.int therefore sees at most 1/delay req/s however many workers
      # run. Its WAF answers 503 on `/rec` and a 302 to notfound.aspx on `/pub`
      # when pushed; 0.4 s tripped it mid-run, 1 s did not.
      def self.delay
        (ENV["RELATON_ITU_DELAY"] || 1.0).to_f
      end

      # @return [Symbol] :top_up or :full
      def self.mode
        ENV["RELATON_ITU_MODE"].to_s == "top_up" ? :top_up : :full
      end

      # ITU-T harvester: one searchRecs request enumerates every edition and
      # supplement; each row is then enriched with getRecHdrDetail-sourced fields
      # (abstract, ISO co-id, editorial-group contributors, status), so harvested
      # records match the live runtime output. Enrichment is up to 4 requests per
      # record — the bulk of the crawl's cost — so the rows are spread over a
      # worker pool (see .concurrency) and progress is logged.
      #
      # Two things keep that cost down. The rows are enqueued **grouped by
      # recommendation**, and the pool shares one FamilyCache, so the two
      # endpoints that answer per *recommendation* rather than per *edition*
      # (`getRecEditions` and the ~90 KB `rec.aspx` page) are fetched once per
      # family instead of once per edition — H.264 alone was asking ITU the same
      # question 21 times. And `mode: :top_up` skips a family the dataset already
      # holds entirely, decided with no HTTP at all (see #held_t?).
      #
      # Each worker owns its own Mechanize agent: Mechanize is not thread-safe,
      # and per-worker agents also keep one worker's cookie/history state out of
      # another's. Rows carry their searchRecs position so #write_file can pick a
      # deterministic winner for duplicate filenames.
      def fetch_recommendations(mode: self.class.mode)
        # `pos` is fixed HERE, against the unreordered searchRecs result, and
        # keeps exactly its current meaning. Only the enqueue ORDER changes
        # below, which #write_file's max-by-position rule is already immune to —
        # it has to be, since worker completion order was never deterministic.
        work = search_recs.each_with_index.to_a
        work = top_up_rows(work) if mode == :top_up
        work = self.class.group_by_family(work)
        cache = self.class.family_cache

        n = self.class.concurrency
        agents = Array.new(n) { rec_agent }
        queue = SizedQueue.new(n * 2)
        workers = agents.map { |agent| spawn_rec_worker(queue, agent, work.size, cache) }
        work.each { |pair| queue << pair }
        n.times { queue << nil } # poison pills
        workers.each(&:join)
        Util.info "ITU-T: detail cache #{cache.stats[:hits]} hits / #{cache.stats[:misses]} misses"
        report_enrichment_failures work.size
      ensure
        agents&.each(&:shutdown)
      end

      # Does the dataset already hold this ITU-T edition? Answered from the
      # searchRecs row alone, which is what lets a top-up decide *before* paying
      # the four detail requests — the ITU-T counterpart of #held?.
      #
      # HTTP-free, and provably so: DataParserT.fetch_docid reads only
      # `row["rec_name"]`, normalizes it with one #sub, and builds a
      # Docidentifier. It takes no agent and touches none of the enrichment path.
      #
      # The filename it derives is the one #write_file would produce: that method
      # uses `docidentifier.find(&:primary).content`, and DataParserT.parse puts
      # the ITU docid first (`docid + enr[:iso]`) — which matters, because an
      # enriched record's ISO co-identifier is *also* `primary: true`.
      #
      # @param row [Hash] a searchRecs row
      # @return [Boolean]
      def held_t?(row)
        did = DataParserT.fetch_docid(row).first
        did && File.exist?(output_file(did.content))
      end

      # Narrow a top-up to the rows worth re-harvesting.
      #
      # The unit is the **family, not the row**. A new edition changes its
      # siblings' `hasEdition` relations, so topping up only the new row would
      # leave the rest of the family on disk pointing at an incomplete edition
      # list — a staleness the full run's wipe-and-rebuild never had. If any row
      # of a family is new, every row of that family is re-harvested; the extra
      # cost is one getRecHdrDetail per sibling, since the family-invariant
      # fetches are shared by the cache.
      #
      # @param work [Array<Array(Hash, Integer)>] [row, searchRecs position]
      # @return [Array<Array(Hash, Integer)>]
      def top_up_rows(work)
        kept = work.group_by { |row, _pos| self.class.family_key(row) }
                   .select { |_key, pairs| pairs.any? { |row, _pos| !held_t?(row) } }
                   .values.flatten(1)
        Util.info "ITU-T (top_up): #{kept.size}/#{work.size} rows in families with new editions"
        kept
      end

      # The recommendation a row is an edition of.
      #
      # Used **only** to decide enqueue order and top-up grouping, never as a
      # cache key: cache correctness is keyed on idrecs ITU's own getRecEditions
      # response supplied (see RecommendationFields#family_id), because two
      # recommendations whose names normalize alike would otherwise silently
      # share metadata. A wrong guess here costs a cache miss, nothing more.
      #
      #   "H.264 (V16) (06/2026)" -> "H.264";  "H Suppl. 1 (05/1999)" -> "H Suppl. 1"
      #
      # @param row [Hash]
      # @return [String]
      def self.family_key(row)
        # Cut at a bare "(" with no leading \s* — an unanchored \s* here is
        # polynomial-time backtracking (CodeQL rb/polynomial-redos).
        DataParserT.normalize_rec_name(row["rec_name"]).sub(/\(.*\z/m, "").strip
      end

      # Make each recommendation's rows contiguous, so its cache entry is still
      # resident when its siblings are enriched. Every [row, pos] pair is carried
      # through untouched. searchRecs already returns name-sorted rows, so on
      # today's data this is close to a no-op — it is a guarantee, not a gain.
      #
      # @param work [Array<Array(Hash, Integer)>]
      # @return [Array<Array(Hash, Integer)>]
      def self.group_by_family(work)
        work.group_by { |row, _pos| family_key(row) }.values.flatten(1)
      end

      # One pool worker: drains the queue with its own agent until the poison
      # pill (nil). Per-row errors are logged and skipped, so one bad row never
      # kills a worker and leaves the queue undrained.
      def spawn_rec_worker(queue, agent, total, cache = NullCache.instance)
        Thread.new do
          while (item = queue.pop)
            row, pos = item
            begin
              errors = Hash.new(true)
              bib = DataParserT.parse(row, agent, errors, cache: cache)
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
