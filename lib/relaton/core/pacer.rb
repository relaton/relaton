# frozen_string_literal: true

module Relaton
  module Core
    #
    # A process-wide, thread-safe request pacer: the whole worker pool between
    # them starts **at most one request per `gap` seconds**.
    #
    # It exists because the two natural alternatives are both wrong for a
    # crawler that has to be polite to one host:
    #
    # * `sleep delay` before each request (what `Relaton::Itu::DataCrawlerR`
    #   did) **adds** the delay to the server's own latency. At ITU's measured
    #   ~1.1 s response time a 1 s delay yields one request every ~2.1 s, so a
    #   ~7k-request crawl spends ~2 h of a ~4 h run doing nothing at all — and
    #   the crawl is pinned to one thread, because the pacing *is* the loop.
    # * a per-worker gap (`Relaton::Cie::DataFetcher::Pacing`) lets N workers
    #   issue N requests per gap. That is right for CIE, where the point is to
    #   let one struggling worker slow itself without dragging the others down,
    #   and wrong here, where the budget belongs to the host.
    #
    # This reserves a *slot* instead: each caller takes the next free instant on
    # a shared timeline and sleeps only until it arrives. The server's latency
    # therefore counts toward the gap rather than being added on top, so the
    # rate the host sees is exactly `1 / gap` no matter how many workers there
    # are — and workers exist only to hide latency, never to raise the rate.
    #
    # The mutex is held for the reservation and **never across the sleep**, so a
    # waiting worker cannot stop another from reserving.
    #
    # Idle time does not bank up slots: a reservation never starts earlier than
    # "now", so a stall elsewhere in the crawl (a governor cooldown, a slow
    # merge) cannot be repaid afterwards as a burst — which is exactly the burst
    # that would re-trip the limiter that caused the stall.
    #
    # `clock:` and `sleeper:` are injectable so specs exercise the arithmetic
    # without wall-clock waits (mirroring `Relaton::Core::Governor`).
    #
    class Pacer
      # How the gap is spent.
      #
      #   :slot   (default) the gap is the minimum interval between request
      #           *starts*, shared by the pool, so the host's own latency counts
      #           toward it. Peak rate 1/gap regardless of worker count.
      #   :fixed  sleep the whole gap before every request, whatever else is
      #           happening. This is what a plain `sleep delay` loop did, kept
      #           as a rollback knob: with one worker it reproduces the old
      #           request pattern exactly — one request per (gap + latency).
      DEFAULT_MODE = :slot

      # @param gap [Numeric] minimum seconds between request *starts*. Zero
      #   disables pacing entirely (used by specs and by cassette replay).
      # @param mode [Symbol] :slot or :fixed, see DEFAULT_MODE
      # @param clock [#call, nil] returns monotonic seconds
      # @param sleeper [#call, nil] receives seconds to sleep
      def initialize(gap:, mode: DEFAULT_MODE, clock: nil, sleeper: nil)
        @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        @sleeper = sleeper || ->(secs) { sleep secs }
        @mutex = Mutex.new
        @gap = coerce_gap(gap)
        @mode = mode == :fixed ? :fixed : DEFAULT_MODE
        @next = nil
        @requests = 0
        @slept = 0.0
      end

      attr_reader :gap, :mode

      # @return [Integer] requests paced so far, for the run summary
      def requests
        @mutex.synchronize { @requests }
      end

      # @return [Float] total seconds spent waiting, for the run summary
      def slept
        @mutex.synchronize { @slept }
      end

      # @param secs [Numeric] the new minimum gap; takes effect on the next
      #   reservation. A negative value is clamped to zero.
      def gap=(secs)
        @mutex.synchronize { @gap = coerce_gap(secs) }
      end

      # Clear the timeline and the counters, so the next caller goes out
      # immediately. For specs, and for a crawl starting a fresh phase.
      def reset!
        @mutex.synchronize do
          @next = nil
          @requests = 0
          @slept = 0.0
        end
      end

      #
      # Reserve the next slot and block until it arrives.
      #
      # @return [Float] seconds actually slept (0.0 when the slot was already
      #   due, which is the common case once the host is slower than the gap)
      #
      def wait
        delay = @mode == :fixed ? @mutex.synchronize { @gap } : (reserve - @clock.call)
        @mutex.synchronize { @requests += 1 }
        return 0.0 unless delay.positive?

        @sleeper.call delay
        @mutex.synchronize { @slept += delay }
        delay
      end

      private

      # Claim the next instant on the shared timeline and advance it. Held under
      # the lock; the waiting happens outside.
      #
      # @return [Float] the instant this caller may start its request
      def reserve
        @mutex.synchronize do
          now = @clock.call
          # `max(now)` is what stops an idle stretch from banking up slots: the
          # timeline catches up to the present rather than paying out a burst.
          @next = @next.nil? || @next < now ? now : @next
          reserved = @next
          @next += @gap
          reserved
        end
      end

      def coerce_gap(secs)
        [secs.to_f, 0.0].max
      end
    end
  end
end
