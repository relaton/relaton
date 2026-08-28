require "relaton/core"
require "w3c_api"
require_relative "../w3c"
require_relative "safe_realize"
require_relative "data_parser"

module Relaton
  module W3c
    class DataFetcher < Core::DataFetcher
      include Relaton::W3c::SafeRealize

      # Raised when pagination over the specifications index stops before the
      # last page (e.g. a page fetch fails after retries, or the API reports
      # more pages than were reached). It aborts the whole crawl so a truncated
      # dataset is never saved or committed — see #fetch and #enqueue_specs.
      class CrawlIncompleteError < StandardError; end

      # Conservative default: too many parallel workers burst the per-spec
      # version-history requests fast enough to trip the W3C API rate limiter
      # (429s), which is what silently truncated the dataset before the crawl
      # learned to abort on incomplete pagination. Raise it via the env var on
      # a faster/shallower run; lower it further if 429s still appear.
      DEFAULT_CONCURRENCY = 4

      # How many times #fetch_specifications_page retries a transient failure
      # (rate-limit/connection) before giving up and aborting the crawl.
      PAGE_FETCH_ATTEMPTS = 3

      # How many resources may be lost to rate limiting before the dataset is
      # considered too incomplete to save. Deliberately low: crawls are bimodal
      # — a healthy run loses none (Aug 17 2026: 0), a rate-limited one loses
      # hundreds (Aug 19 2026: 1,412) — so there is no middle ground to protect.
      # Genuinely broken resources (permanent skips from 404s/5xx) are counted
      # separately and stay tolerated.
      DEFAULT_MAX_THROTTLED_LOSSES = 25

      # Retry policy pushed into w3c_api. Its defaults spend ~31s (1+2+4+8+16)
      # inside lutaml-hal before a 429 ever reaches us, which just delays the
      # shared back-pressure that actually works; this compresses the same chain
      # to ~11s (0.5+1+2+4+4) so the Governor can open its pool-wide cooldown
      # while the ban window is still young.
      #
      # `max_retries` deliberately stays at 5. lutaml-hal applies one retry count
      # to both 429 and 5xx, and unlike a 429 a 5xx is still a *permanent* skip
      # here — cutting its attempts would blacklist a burst of resources on a
      # brief upstream wobble that the old policy rode out, and `skipped` is not
      # counted by guard_throttle_budget, so that loss would be invisible.
      UPSTREAM_RATE_LIMITING = {
        max_retries: 5, base_delay: 0.5, max_delay: 4.0, backoff_factor: 2.0
      }.freeze

      # Ceiling on resources dropped to rate limiting before the crawl refuses
      # to save. Tunable via env var for a deliberately partial run; 0 is a
      # meaningful setting (tolerate nothing), so it is accepted here unlike in
      # the governor's duration knobs.
      def self.max_throttled_losses
        value = ENV["RELATON_W3C_MAX_THROTTLED"].to_s.strip
        value.match?(/\A\d+\z/) ? value.to_i : DEFAULT_MAX_THROTTLED_LOSSES
      end

      # Number of fetch_spec worker threads. Tunable via env var so CI or
      # local runs can dial it up for speed or down to lighten load on
      # api.w3.org (or for debugging).
      def self.concurrency
        (ENV["RELATON_W3C_FETCH_CONCURRENCY"] || DEFAULT_CONCURRENCY).to_i
      end

      # Whether to crawl each specification's version history (version_history,
      # predecessor_versions, successor_versions). Enabled by default for a
      # complete dataset. Set RELATON_W3C_FETCH_VERSIONS=false for a faster,
      # shallower crawl that emits only the top-level specifications and skips
      # the per-spec version fan-out (the bulk of the API requests).
      def self.fetch_versions?
        val = ENV["RELATON_W3C_FETCH_VERSIONS"]
        return true if val.nil? || val.empty?

        !%w[0 false no off].include?(val.strip.downcase)
      end

      def initialize(*args)
        super
        @mutex = Mutex.new
        @interrupted = false
      end

      # The index is pubid-backed: `pubid_class:` makes Relaton::Index sort the
      # rows by `id.root.number` on save and serialize each id to its
      # `_type: pubid:w3c:*` hash. Without it a v1-shaped file would be written
      # under a v2 name, with no error and no narrowing.
      def index
        @index ||= Relaton::Index.find_or_create(
          :W3C, file: "#{INDEXFILE}.yaml", pubid_class: ::Pubid::W3c::Identifier
        )
      end

      def log_error(msg)
        Util.error msg
      end

      def client
        @client ||= W3cApi::Client.new
      end

      #
      # Parse documents in parallel. The crawler is heavily I/O-bound on
      # api.w3.org round-trips (~30-50k requests per run), so a small thread
      # pool gives a near-linear speedup. Pagination still happens serially:
      # each page's `next?` flag gates whether the next page is requested.
      #
      # A SIGINT (Ctrl-C) is handled gracefully: the producer stops queuing and
      # the workers stop processing after their in-flight spec, then the index
      # of everything fetched so far is saved rather than the run being lost.
      #
      def fetch(_source = nil)
        SafeRealize.reset!
        configure_upstream_rate_limiting
        n_workers = self.class.concurrency
        queue = SizedQueue.new(n_workers * 4)
        workers = Array.new(n_workers) { spawn_worker(queue) }

        with_interrupt_handler do
          # The poison pills + join run in `ensure` so an exception raised while
          # enqueuing (e.g. CrawlIncompleteError) still unblocks the producer
          # and drains the workers instead of deadlocking on queue.pop.
          begin
            enqueue_specs(queue)
          ensure
            n_workers.times { queue << nil } # poison pills
            workers.each(&:join)
          end
          if @interrupted
            # Ctrl-C means "give me what you have", so the completeness guards
            # below are deliberately not applied to an interrupted crawl.
            Util.warn "Crawl interrupted — saving progress collected so far."
          else
            guard_rate_limited
            guard_throttle_budget
          end
          index.save
        end

        report_errors
      end

      # Abort when the governor concluded we are banned rather than briefly
      # throttled. Everything fetched so far is discarded on purpose: a partial
      # dataset must never be saved (crawler.rb wipes data/ first, so saving one
      # commits mass deletions).
      def guard_rate_limited
        return unless SafeRealize.governor.exhausted?

        raise CrawlIncompleteError,
              "crawl is rate-limited: gave up after " \
              "#{SafeRealize.governor.throttle_rounds} consecutive backoffs " \
              "(#{SafeRealize.governor.throttle_count} rate-limited responses); " \
              "refusing to save a partial dataset"
      end

      # The per-resource counterpart to guard_complete_pagination: pagination can
      # complete cleanly while rate limiting has quietly hollowed out the
      # documents behind it.
      def guard_throttle_budget
        lost = SafeRealize.throttled.size
        budget = self.class.max_throttled_losses
        return if lost <= budget

        raise CrawlIncompleteError,
              "#{lost} resources were dropped to rate limiting (budget #{budget}); " \
              "refusing to save a partial dataset"
      end

      #
      # Page through the specifications index, feeding each spec (paired with
      # its embedded page) to the worker queue. Returns early when interrupted.
      #
      # embed: true inlines each specification's full payload into the index
      # page's `_embedded` block, so a spec link realizes from that page in
      # memory instead of making its own HTTP request — one request per page
      # rather than one per specification. The page is queued alongside each
      # link so the worker can hand it back to realize as the parent_resource.
      #
      def enqueue_specs(queue)
        specs = client.specifications(embed: true)
        expected_pages = specs.pages
        last_page = nil
        loop do
          page = specs
          page.links.specifications.each do |spec|
            break if stopping?

            queue << [spec, page]
          end
          break if stopping?

          last_page = page.page
          break unless page.next?

          # Fetch the next page through the client's fetch path rather than
          # realizing the `next` link: only fetch populates the page's
          # embedded_data, so this keeps embed working past page 1. Realizing
          # the `next` link drops `_embedded` and forces a per-spec HTTP
          # request for every specification on every later page.
          next_page = fetch_specifications_page(page.page + 1)
          # A nil here means the page fetch failed after retries (not the end
          # of the list — that is `!page.next?` above). Aborting rather than
          # `break`ing prevents a rate-limit blip from silently truncating the
          # dataset: a partial crawl must never be saved/committed.
          unless next_page
            # When the governor gave up, the page didn't fail — we stopped
            # asking. Let guard_rate_limited report that with the accurate
            # reason instead of dressing it up as a pagination fault.
            break if SafeRealize.governor.exhausted?

            raise CrawlIncompleteError,
                  "specifications pagination stopped at page #{page.page}: " \
                  "failed to fetch page #{page.page + 1}"
          end

          specs = next_page
        end

        return if stopping?

        guard_complete_pagination(last_page, expected_pages)
      end

      # Reasons to stop feeding the queue: a Ctrl-C (save what we have) or the
      # governor concluding the crawl is banned (abort). Both need the producer
      # to stop; #fetch decides which of the two it was.
      def stopping?
        @interrupted || SafeRealize.governor.exhausted?
      end

      # Defense in depth: even when no page fetch raised, make sure pagination
      # actually reached the last page the API advertised. Catches truncation
      # modes other than a failed fetch (e.g. a `next` link that goes missing).
      # Only enforced when the index reported a positive page count.
      def guard_complete_pagination(last_page, expected_pages)
        return unless expected_pages.is_a?(Integer) && expected_pages.positive?
        return unless last_page.is_a?(Integer) && last_page < expected_pages

        raise CrawlIncompleteError,
              "specifications pagination ended at page #{last_page} of " \
              "#{expected_pages}; refusing to save a partial dataset"
      end

      def fetch_spec(unrealized_spec, page = nil)
        # When `page` came from an embed:true fetch, realizing against it as the
        # parent_resource serves the spec from embedded data (no HTTP request).
        spec = realize(unrealized_spec, parent_resource: page)
        return unless spec

        local_errors = Hash.new(true)
        save_doc DataParser.parse(spec, local_errors)

        fetch_versions(spec) if self.class.fetch_versions?

        @mutex.synchronize { local_errors.each { |k, v| @errors[k] &&= v } }
      end

      #
      # Crawl a specification's version history: its dated editions plus the
      # predecessor/successor version chains. Each entry is a separate HTTP
      # request, so this is the bulk of a run and can be skipped via
      # RELATON_W3C_FETCH_VERSIONS=false (see .fetch_versions?).
      #
      def fetch_versions(spec)
        if spec.links.respond_to?(:version_history) && spec.links.version_history
          version_history = realize spec.links.version_history
          version_history&.links&.spec_versions&.each { |version| parse_and_save version }
        end

        if spec.links.respond_to?(:predecessor_versions) && spec.links.predecessor_versions
          predecessor_versions = realize spec.links.predecessor_versions
          predecessor_versions&.links&.predecessor_versions&.each { |version| parse_and_save version }
        end

        return unless spec.links.respond_to?(:successor_versions) && spec.links.successor_versions

        successor_versions = realize spec.links.successor_versions
        successor_versions&.links&.successor_versions&.each { |version| parse_and_save version }
      end

      #
      # Save document to file
      #
      # @param [Relaton::W3c::ItemData, nil] bib bibliographic item
      #
      def save_doc(bib, warn_duplicate: true)
        return unless bib

        file = file_name(bib.docnumber)
        @mutex.synchronize do
          if @files.include?(file)
            Util.warn "File #{file} already exists. Document: #{bib.docnumber}" if warn_duplicate
          else
            index_primary bib.docidentifier&.detect(&:primary), file
            @files << file
          end
          File.write file, serialize(bib), encoding: "UTF-8"
        end
      end

      #
      # Add a document's primary id to the index.
      #
      # Every W3C id is expected to parse. One that does not is recorded in
      # `@errors`, so the inherited `report_errors` logs it at ERROR and raises
      # a tracked GitHub issue at the end of the crawl, and the row is skipped
      # rather than indexed unparsed: `Relaton::Index` rejects the WHOLE index
      # if a single row fails to deserialize, and its sort calls
      # `.root.number` on every id. The data file is still written, so the
      # document is unindexed, never lost.
      #
      # Keyed by the ID rather than the output path: the id is the defect, the
      # file is only where it landed, and one broken id reaching several files
      # must still report once.
      #
      # @param [Docidentifier, nil] docid the document's primary identifier
      # @param [String] file path the document was written to
      #
      def index_primary(docid, file)
        if docid&.pubid
          index.add_or_update docid.pubid, file
          return
        end

        id = docid&.content || file
        @errors[id.to_s] = "Unparseable primary id `#{id}` was not indexed (#{file})"
      end

      def to_xml(bib)
        bib.to_xml(bibdata: true)
      end

      def to_yaml(bib)
        bib.to_yaml
      end

      def to_bibxml(bib)
        bib.to_xml
      end

      #
      # Generate file name
      #
      # @param [String] id document id
      #
      # @return [String] file name
      #
      def file_name(id)
        name = id.sub(/^W3C\s/, "").gsub(/[\s,:\/+]/, "_").squeeze("_").downcase
        File.join @output, "#{name}.#{@ext}"
      end

      private

      # Install a SIGINT handler for the duration of the crawl so Ctrl-C sets
      # the @interrupted flag (observed by the producer loop and the workers)
      # instead of killing the process mid-write. The trap body is kept minimal
      # (no I/O or locking) because trap context is restricted; the user-facing
      # notice is printed from the main thread once the crawl winds down. The
      # previous handler is restored on the way out so the trap doesn't leak
      # into the host process.
      def with_interrupt_handler
        previous = Signal.trap("INT") { @interrupted = true }
        yield
      ensure
        Signal.trap("INT", previous || "DEFAULT")
      end

      # Fetch one page of the specifications index with embed enabled. Goes
      # through the client (the register's fetch path) so the page's
      # embedded_data is populated. Transient 403/5xx/connection failures are
      # already retried upstream (w3c_api/lutaml-hal), but losing an index page
      # drops every spec on it, so retry a few more times here with backoff to
      # ride out a brief wobble. Rate limiting is handled separately, by the
      # governor. Returns nil once the attempts are exhausted (or the crawl is
      # declared banned); the caller turns that into a CrawlIncompleteError so
      # the crawl aborts instead of committing a truncated dataset.
      def fetch_specifications_page(number)
        attempt = 0
        begin
          SafeRealize.governor.wait
          page = client.specifications(embed: true, page: number)
          SafeRealize.governor.succeeded!
          page
        rescue *Governor::THROTTLE_ERRORS => e
          # How long to keep trying a rate-limited page is the governor's call,
          # not this counter's: PAGE_FETCH_ATTEMPTS would give up after ~3
          # minutes and report a *pagination* fault, hiding the real reason and
          # pre-empting the escalation ladder. Retry until the governor declares
          # the crawl banned; #wait above paces each attempt, and returns
          # immediately once it has, so this cannot spin.
          log_error "Rate-limited fetching specifications page #{number}: #{e.message}"
          return nil if SafeRealize.governor.throttled!(retry_after: Governor.retry_after(e))

          retry
        rescue Lutaml::Hal::Error, Faraday::Error => e
          attempt += 1
          log_error "Failed to fetch specifications page #{number} " \
                    "(attempt #{attempt}/#{PAGE_FETCH_ATTEMPTS}): " \
                    "#{e.class}: #{e.message}"
          if attempt < PAGE_FETCH_ATTEMPTS
            sleep(2**attempt)
            retry
          end
          nil
        end
      end

      # Point w3c_api's rate limiter at UPSTREAM_RATE_LIMITING. This mutates
      # w3c_api's process-wide singleton and is not restored afterwards — the
      # crawler is a standalone script, and a shorter inner retry is the right
      # setting for any caller that has the governor in front of it anyway.
      # Best-effort: the setter is w3c_api's only public knob and is not part of
      # a stable contract, so losing it must not fail the run.
      def configure_upstream_rate_limiting
        hal = W3cApi::Hal.instance
        return unless hal.respond_to?(:configure_rate_limiting)

        # w3c_api >= 0.3.3 cascades this through reset_client -> rebuild_register
        # itself, so the register no longer goes on serving the old policy.
        # Do NOT add a reset_register call after this: rebuild_register
        # re-registers eagerly on purpose (Link#realize raises when the name is
        # absent from lutaml-hal's GlobalRegister), and tearing it back down
        # would break realize for every model fetched before this point.
        hal.configure_rate_limiting(UPSTREAM_RATE_LIMITING)
      rescue StandardError => e
        Util.warn "Could not configure w3c_api rate limiting: #{e.class}: #{e.message}"
      end

      def spawn_worker(queue)
        Thread.new do
          while (item = queue.pop)
            # Once stopping, drain the queue without processing so the producer
            # unblocks and the pool reaches its poison pills quickly.
            next if stopping?

            spec, page = item
            begin
              fetch_spec spec, page
            rescue StandardError => e
              log_error "fetch_spec failed: #{e.class}: #{e.message}\n" \
                        "#{e.backtrace.first(5).join("\n")}"
            end
          end
        end
      end

      def parse_and_save(version)
        realized = realize version
        save_doc DataParser.parse(realized) if realized
      end
    end
  end
end
