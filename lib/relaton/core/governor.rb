# frozen_string_literal: true

require "time" # Time.parse, for an HTTP-date Retry-After

module Relaton
  module Core
    #
    # Process-wide, thread-safe rate-limit back-pressure for a crawl.
    #
    # Promoted here from `Relaton::W3c::Governor`, which is now a thin binding
    # of it, when the ITU-R crawler became the second flavor to need
    # cross-thread throttling. What stays with a flavor is only which errors
    # mean "throttled" (THROTTLE_ERRORS / .throttle?) and which env vars tune it
    # (ENV_PREFIX); the ladder, the jitter, the give-up latch and the
    # Retry-After parsing are shared.
    #
    # The problem it solves, as first met on api.w3.org: that host sits behind
    # Cloudflare, whose rate limiting is bimodal — a run either never trips it
    # or trips it and stays banned for hours. Before this
    # existed, each of the crawl's workers reacted to its own 429s in isolation
    # with a backoff capped at ~31s — far too short to outlast the ban, and the
    # retries themselves kept the limiter engaged. The Aug-2026 crawl spent 4h56m
    # doing nothing but re-tripping the limiter, permanently discarding 1,412
    # documents, before it aborted.
    #
    # The governor gives the whole worker pool one shared cooldown. When any
    # thread sees a 429 it opens (or extends) that cooldown; every other thread
    # observes it in #wait. Cooldowns escalate per *round* — 60s, 120s, ... to a
    # 15-minute cap — and after GIVE_UP_AFTER consecutive rounds without a single
    # success the crawl is declared rate-limited and gives up (~15 min) so CI
    # fails fast instead of grinding for five hours.
    #
    # `clock:` and `sleeper:` are injectable so specs exercise the real
    # arithmetic without wall-clock waits.
    #
    class Governor
      # First cooldown, in seconds. Deliberately minute-scale: a Cloudflare ban
      # window outlasts any second-scale backoff.
      BASE_COOLDOWN = 60

      # Ceiling for a single cooldown, including a server-supplied Retry-After
      # (which must not be able to park a worker for an hour).
      MAX_COOLDOWN = 900

      # Consecutive throttle rounds with no intervening success before the crawl
      # is considered banned. With the ladder above that is ~15 min of cooldown
      # (60+120+240+480 s; the fifth round latches before its own wait).
      GIVE_UP_AFTER = 5

      # Fraction of the cooldown added as random jitter, so the workers do not
      # all resume on the same instant and immediately re-trip the limiter.
      JITTER_FRACTION = 0.1

      # Which errors mean "you are being rate-limited", as opposed to "this
      # resource is broken". Core ships none: the distinction is the one thing
      # only the flavor knows, and getting it wrong in either direction is
      # expensive — a broken resource routed here opens a pool-wide cooldown
      # for one bad record, and a throttle routed the other way gets recorded
      # as permanent data loss (which is exactly what the W3C crawl did before
      # this class existed). Subclasses override the constant, or #throttle?
      # when the signal is a status code rather than an exception class.
      THROTTLE_ERRORS = [].freeze

      # Prefix for the three duration knobs, so two flavors crawling in one
      # process cannot share a cooldown ladder by accident. A subclass sets its
      # own ("RELATON_W3C", "RELATON_ITU"); the suffixes are fixed.
      ENV_PREFIX = "RELATON"

      # Whether this error means the server is rate-limiting us.
      #
      # Class membership is the common case. A flavor whose server signals
      # throttling with a *status code* on a shared exception class (ITU: 503 on
      # /rec) overrides this instead of the constant.
      #
      # @param error [StandardError]
      # @return [Boolean]
      def self.throttle?(error)
        self::THROTTLE_ERRORS.any? { |klass| error.is_a? klass }
      end

      attr_reader :base, :max, :give_up_after, :env_prefix

      def initialize(base: nil, max: nil, give_up_after: nil,
                     clock: nil, sleeper: nil, jitter: nil, env_prefix: nil)
        @env_prefix = env_prefix || self.class::ENV_PREFIX
        # Remembered so #reset! can re-read the env knobs for the next crawl
        # without discarding values a caller passed explicitly.
        @overrides = { base: base, max: max, give_up_after: give_up_after }
        load_limits
        @clock = clock || -> { Time.now }
        @sleeper = sleeper || ->(secs) { sleep secs }
        @jitter = jitter || ->(secs) { Kernel.rand * secs * self.class::JITTER_FRACTION }
        @mutex = Mutex.new
        @cooldown_until = nil
        @penalty = nil
        @rounds = 0
        @events = 0
        @abandoned = false
        @abandoned_rounds = nil
      end

      #
      # Block until the shared cooldown expires. Called before every request.
      #
      # The mutex is never held across the sleep — the deadline is read under
      # the lock and the sleeping happens outside it, so a cooling-down worker
      # cannot block another thread from recording its own throttle.
      #
      # @return [Numeric] seconds actually slept (0.0 when there was nothing to
      #   wait for, including once the crawl has given up)
      #
      def wait
        slept = 0.0
        waited_for = nil
        loop do
          # Once we have given up there is nothing left to wait for, and stalling
          # here would delay the shutdown by up to a full cooldown.
          deadline, remaining = @mutex.synchronize do
            gave_up? ? [nil, 0.0] : [@cooldown_until, cooldown_remaining]
          end
          break unless remaining.positive?
          # Re-check after sleeping so a cooldown *extended* mid-round (a later
          # Retry-After asking for longer) also holds back the workers already
          # sleeping — they would otherwise wake on the stale deadline and
          # re-trip the limiter. Looping only on a later deadline keeps a stalled
          # clock from spinning here.
          break if waited_for && deadline && deadline <= waited_for

          waited_for = deadline
          delay = remaining + @jitter.call(remaining)
          @sleeper.call(delay)
          slept += delay
        end
        slept
      end

      #
      # Record a 429 and open/extend the shared cooldown.
      #
      # @param retry_after [Integer, nil] seconds from the response's Retry-After
      #
      # @return [Boolean] true when the crawl should give up
      #
      def throttled!(retry_after: nil)
        @mutex.synchronize do
          now = @clock.call
          @events += 1
          if @cooldown_until.nil? || now >= @cooldown_until
            open_round(now, retry_after)
          elsif retry_after
            # Mid-round, the server may still ask for longer than we planned.
            extend_round(now + capped(retry_after))
          end
          # Giving up latches. Otherwise a straggler worker succeeding after the
          # producer already stopped paginating would clear @rounds and let the
          # crawl save the truncated index it just decided to abandon.
          #
          # @rounds is snapshotted at the same moment, because #succeeded!
          # resets it: read afterwards it names whatever has re-accumulated
          # since, not the threshold that was crossed. The abort message is
          # the only place an operator learns why the crawl stopped.
          unless @abandoned
            @abandoned = @rounds >= @give_up_after
            @abandoned_rounds = @rounds if @abandoned
          end
          @abandoned
        end
      end

      #
      # Record a successful request: the limiter has released us.
      #
      def succeeded!
        @mutex.synchronize do
          @rounds = 0
          @cooldown_until = nil
          # Decay rather than reset, so a limiter that keeps flapping still
          # climbs the ladder instead of restarting at `base` every time.
          @penalty = @penalty && @penalty > @base ? [@penalty / 2.0, @base].max : nil
        end
      end

      # @return [Boolean] give_up_after consecutive rounds passed with no success
      def exhausted?
        @mutex.synchronize { gave_up? }
      end

      # Clear all state for a fresh crawl. Resets in place rather than handing
      # back a new object so callers (and specs) holding this instance keep
      # observing the live governor.
      def reset!
        @mutex.synchronize do
          load_limits
          @cooldown_until = nil
          @penalty = nil
          @rounds = 0
          @events = 0
          @abandoned = false
          @abandoned_rounds = nil
        end
      end

      # @return [Integer] consecutive throttle rounds since the last success
      def throttle_rounds
        @mutex.synchronize { @rounds }
      end

      # The consecutive-round count as it stood when the give-up latched, for
      # the abort message. Distinct from #throttle_rounds, which stays LIVE
      # because a crawler logs it per retry as the current round (see
      # Relaton::Itu::DataCrawlerR) and #succeeded! resets it.
      #
      # @return [Integer, nil] nil while the crawl is still running
      def give_up_rounds
        @mutex.synchronize { @abandoned_rounds }
      end

      # @return [Integer] every 429 observed, for reporting
      def throttle_count
        @mutex.synchronize { @events }
      end

      #
      # Seconds requested by a rate-limited response's Retry-After header.
      #
      # lutaml-hal >= 0.2.5 carries a `{ status:, headers: }` hash on every error
      # mapped from a response (nil for locally raised ones), so anything without
      # one yields nil.
      #
      # @param error [StandardError]
      #
      # @return [Integer, nil]
      #
      def self.retry_after(error)
        return nil unless error.respond_to?(:response)

        response = error.response
        headers = response.is_a?(Hash) ? (response[:headers] || response["headers"]) : nil
        return nil unless headers.respond_to?(:[])

        seconds_from headers["retry-after"] || headers["Retry-After"]
      end

      #
      # Retry-After is either delta-seconds or an HTTP-date (RFC 9110). The date
      # form is parsed properly rather than by scanning digits, which would pick
      # up the day-of-month and back off for a wildly wrong duration; a date
      # already in the past yields 0, i.e. "no extra floor".
      #
      def self.seconds_from(value)
        str = value.to_s.strip
        return nil if str.empty?
        return str.to_i if str.match?(/\A\d+\z/)

        begin
          [(Time.parse(str) - Time.now).ceil, 0].max
        rescue ArgumentError
          nil
        end
      end

      # A blank or non-positive override is treated as unset.
      def self.env_int(name, default)
        value = ENV[name].to_s.strip
        return default if value.empty?

        parsed = value.to_i
        parsed.positive? ? parsed : default
      end

      private

      # "<PREFIX>_THROTTLE_<SUFFIX>", the one thing ENV_PREFIX exists for.
      def env_name(suffix)
        "#{@env_prefix}_THROTTLE_#{suffix}"
      end

      # Read the duration knobs, letting explicit constructor args win over the
      # environment. Re-read on #reset! so the env vars behave like a flavor's
      # sibling knobs, which are class methods evaluated per crawl rather than
      # frozen when the flavor was autoloaded.
      def load_limits
        @base = @overrides[:base] || self.class.env_int(env_name("BASE"), self.class::BASE_COOLDOWN)
        @max = @overrides[:max] || self.class.env_int(env_name("MAX"), self.class::MAX_COOLDOWN)
        @give_up_after = @overrides[:give_up_after] ||
          self.class.env_int(env_name("GIVEUP"), self.class::GIVE_UP_AFTER)
      end

      # Start a new escalation step. Retry-After raises the floor but never
      # lowers our own ladder — the server's hint is a minimum, not a discount.
      def open_round(now, retry_after)
        @rounds += 1
        ladder = @penalty ? [@penalty * 2, @max].min : @base
        hint = retry_after ? capped(retry_after) : 0
        @penalty = [ladder, hint].max
        @cooldown_until = now + @penalty
      end

      def extend_round(deadline)
        @cooldown_until = deadline if deadline > @cooldown_until
      end

      def cooldown_remaining
        return 0.0 unless @cooldown_until

        [@cooldown_until - @clock.call, 0.0].max
      end

      def capped(seconds)
        [seconds, @max].min
      end

      # Callers must already hold the mutex. Latched by #throttled! — never
      # recomputed from @rounds, which #succeeded! resets.
      def gave_up?
        @abandoned
      end
    end
  end
end
