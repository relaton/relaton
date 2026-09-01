require "concurrent/map"
require_relative "governor"

module Relaton
  module W3c
    # Thin wrapper over lutaml-hal's `realize`. Successful objects are cached by
    # w3c_api (it caches realized objects keyed by URL), so this only remembers
    # resources that failed terminally and returns nil for them — so one broken
    # link doesn't abort the crawl and isn't re-fetched on every reference.
    #
    # Transient failures are retried upstream first: w3c_api retries 403 (the
    # W3C rate-limit signal) and connection/timeout errors, and lutaml-hal
    # retries 429 and 5xx. By the time an error surfaces here the resource is
    # either genuinely broken (skipped for the rest of the run) or we are still
    # being rate-limited (handed to the Governor).
    #
    # That distinction is the point: a 429 or 403 means "come back later", not
    # "this document does not exist". Recording one as a permanent skip is what
    # silently cost the Aug-2026 relaton-data-w3c crawl 1,412 documents.
    module SafeRealize
      # How many times a rate-limited realize is re-attempted, each behind the
      # governor's shared cooldown, before the resource is written off for this
      # run. Three spans the escalating cooldowns without letting one unlucky
      # href monopolise a worker.
      THROTTLE_ATTEMPTS = 3

      # Hrefs that failed terminally — one map shared by every includer
      # (DataFetcher and DataParser) since a broken resource is broken for the
      # whole crawl. Initialized eagerly (at load, single-threaded) so the
      # parallel fetcher's first concurrent access can't race a lazy `||=`;
      # Concurrent::Map then handles the concurrent reads/writes.
      @skipped = Concurrent::Map.new

      # Hrefs lost to rate limiting rather than to a broken resource. Kept apart
      # from @skipped because they measure how incomplete the crawl is, not a
      # property of the resource: DataFetcher refuses to save an index once too
      # many pile up.
      @throttled = Concurrent::Map.new

      # Shared back-pressure for the whole crawl (see Governor).
      @governor = Governor.new

      class << self
        attr_reader :skipped, :throttled
        attr_accessor :governor

        # Start a crawl (or a spec example) from a clean slate. The governor is
        # reset in place, so a reference taken before the reset stays live.
        def reset!
          @skipped.clear
          @throttled.clear
          @governor.reset!
        end
      end

      # @param parent_resource [Object, nil] the index/page the link came from.
      #   When the page was fetched with `embed: true`, its inlined `_embedded`
      #   payload lets the link realize from memory instead of issuing an HTTP
      #   request. nil (the default) preserves the plain remote-fetch behavior.
      def realize(obj, parent_resource: nil)
        # Once the governor has latched its give-up the run is already lost
        # (DataFetcher#guard_rate_limited raises and nothing is saved) and the
        # host has just banned us, so every further request only extends the
        # ban into the next run. #wait alone stops WAITING, not asking: the
        # 2026-08-31 crawl spent its last 11 minutes firing at a banned host
        # because the per-spec fan-out had no back-pressure of its own.
        #
        # This is the one choke point every request in the crawl passes
        # through, so one check covers DataFetcher#fetch_versions and all
        # seven of DataParser's realize sites. They already tolerate nil —
        # that is the SafeRealize contract.
        return nil if SafeRealize.governor.exhausted?

        href = resolve_href(obj)
        return nil if SafeRealize.skipped.key?(href)

        attempt = 0
        begin
          attempt += 1
          SafeRealize.governor.wait
          realized = obj.realize(parent_resource: parent_resource)
          # Only a realize that actually went to the network says anything about
          # the limiter. With a parent_resource, lutaml-hal serves the object
          # straight out of the page's `_embedded` payload and never issues a
          # request (link.rb: "Priority 1: check embedded content first") — and
          # that is the common case, one per specification. Reporting those as
          # successes would clear the cooldown and reset the escalation ladder
          # between every pair of version-history 429s, so the governor could
          # never reach its give-up threshold: exactly the 60s re-trip loop this
          # class exists to break.
          SafeRealize.governor.succeeded! unless parent_resource
          # The document made it into the dataset after all, so it must stop
          # counting against the crawl's throttle budget.
          SafeRealize.throttled.delete(href)
          realized
        rescue *Governor::THROTTLE_ERRORS => e
          retry if record_throttle(href, e, attempt)
          nil
        rescue Lutaml::Hal::ConnectionError, Lutaml::Hal::TimeoutError, Faraday::Error, Net::OpenTimeout => e
          # Network-level failure (already retried by w3c_api). The resource itself
          # is fine, so don't skip it permanently — a later reference can try again.
          Util.warn "Failed to realize object: #{href}, error: #{e.message}"
          nil
        rescue Lutaml::Hal::NotFoundError
          Util.warn "Object not found: #{href}"
          SafeRealize.skipped[href] = true
          nil
        rescue Lutaml::Hal::Error => e
          # Definitive upstream error (5xx, 400/401, …) already retried by
          # w3c_api / lutaml-hal. Skip the broken/unavailable resource rather than
          # re-hitting it for every link that references it. 5xx stays here
          # deliberately: the handful of persistent per-resource 500s a healthy
          # crawl sees are broken records, not throttling, and routing them
          # through the governor would open a pool-wide cooldown for each one.
          Util.warn "Skipping #{href}, upstream error after retries: #{e.message}"
          SafeRealize.skipped[href] = true
          nil
        end
      end

      private

      #
      # Record a rate-limited attempt and decide whether to try again.
      #
      # @return [Boolean] true to retry — the caller re-enters #realize's begin
      #   block, whose #wait sits out the shared cooldown first
      #
      def record_throttle(href, error, attempt)
        gave_up = SafeRealize.governor.throttled!(
          retry_after: Governor.retry_after(error),
        )
        # Once the governor has declared the crawl rate-limited there is nothing
        # to gain from more attempts — the run is about to abort anyway.
        return true if !gave_up && attempt < THROTTLE_ATTEMPTS

        Util.warn "Throttled out: #{href}, still rate-limited after " \
                  "#{attempt} attempt(s): #{error.message}"
        SafeRealize.throttled[href] = true
        false
      end

      def resolve_href(obj)
        obj.href || obj.links.self.href
      end
    end
  end
end
