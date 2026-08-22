# frozen_string_literal: true

module Relaton
  module Itu
    #
    # Cross-row cache for the ITU-T detail endpoints that answer the same thing
    # for every edition of one recommendation.
    #
    # `searchRecs` runs with `main_edition_flag=0`, so it returns one row **per
    # edition** — ~16k rows over ~7.7k recommendations. Enrichment then costs
    # four www.itu.int requests per row, and three of them are keyed by `idrec`
    # but answer for the whole recommendation. Verified from
    # `spec/itu/vcr_cassettes/itu_t_h_264.yml`: `getRecEditions?idrec=16818` and
    # `?idrec=14659` return **byte-identical** 21-row payloads. H.264's 21
    # editions therefore issue 21 identical requests, and the corpus average is
    # ~2.1 editions per recommendation.
    #
    # The cache is created per crawl by `DataFetcher#fetch_recommendations` and
    # threaded down as a parameter — never global state, and never reachable
    # from the live `Bibliography.get` path, which gets {NullCache} instead.
    #
    # Two locks, and the split matters. `@mutex` guards only the entry *table*;
    # each entry carries its own lock, which the block (an HTTP request) is run
    # under. Holding `@mutex` across the request would serialize all eight
    # workers onto one connection's latency and collapse the pool to one thread;
    # the per-entry lock is also what makes two workers racing on two editions
    # of one recommendation issue **one** request rather than two.
    #
    class FamilyCache
      # Entries resident at once. Bounded because an unbounded cache over ~7.7k
      # recommendations, each holding an editions list and a supplements list,
      # runs to hundreds of MB on a CI runner alongside eight Mechanize agents.
      # With rows enqueued family-by-family only a handful are ever live, so the
      # cap costs no hit rate.
      DEFAULT_MAX_ENTRIES = 512

      Entry = Struct.new(:mutex, :value, :computed)

      def initialize(max_entries: DEFAULT_MAX_ENTRIES)
        @max = [max_entries.to_i, 1].max
        @entries = {}
        @mutex = Mutex.new
        @hits = 0
        @misses = 0
        @evictions = 0
      end

      # Value for `key`, computing it under that key's own lock when absent.
      #
      # A block that raises leaves the entry uncached, so a transient failure is
      # retried by the next caller instead of being served to the whole family
      # as a permanent nil.
      #
      # @param key [Object]
      # @return [Object]
      def fetch(key)
        entry = @mutex.synchronize { touch key }
        entry.mutex.synchronize do
          if entry.computed
            @mutex.synchronize { @hits += 1 }
            next entry.value
          end

          value = yield
          entry.value = value
          entry.computed = true
          @mutex.synchronize do
            @misses += 1
            # Re-publish. The table lock is released between #touch and the
            # entry lock above, and in that window this entry is unlocked and so
            # a valid eviction candidate for another thread's #touch. Nothing
            # wrong is ever served — this thread holds the Entry directly — but
            # without this the write is lost and the next caller pays for the
            # request again. `unless key?` so a replacement entry another thread
            # has since created is not discarded.
            @entries[key] = entry unless @entries.key? key
          end
          value
        end
      end

      # Publish an already-computed value under every other key it also answers.
      #
      # This is what makes one request warm a whole family: a `getRecEditions`
      # response names every sibling `idrec`, and by the endpoint's own testimony
      # the payload for each of them is the same one. An entry whose lock is held
      # is skipped — it is mid-fetch and will land on this value anyway.
      #
      # @param keys [Array<Object>]
      # @param value [Object]
      # @return [Object] value
      def warm(keys, value)
        keys.each do |key|
          entry = @mutex.synchronize { touch key }
          next unless entry.mutex.try_lock

          begin
            next if entry.computed

            entry.value = value
            entry.computed = true
          ensure
            entry.mutex.unlock
          end
        end
        value
      end

      # @return [Boolean] whether this cache actually caches. Callers use it to
      #   skip building a key whose computation would itself cost a request.
      def caching?
        true
      end

      # @return [Hash] for the run summary
      def stats
        @mutex.synchronize do
          { hits: @hits, misses: @misses, entries: @entries.size, evictions: @evictions }
        end
      end

      private

      # Fetch-or-create `key` and mark it most recently used. Callers hold
      # @mutex. Eviction skips an entry currently being computed, so a worker
      # can never lose the entry it is holding.
      def touch(key)
        if @entries.key? key
          entry = @entries.delete key
          return @entries[key] = entry
        end

        evict while @entries.size >= @max
        @entries[key] = Entry.new(Mutex.new, nil, false)
      end

      def evict
        victim = @entries.each_key.find { |k| !@entries[k].mutex.locked? }
        # Everything resident is in flight: grow rather than block a worker.
        return @max = @entries.size + 1 unless victim

        @entries.delete victim
        @evictions += 1
      end
    end

    #
    # The no-op cache: `#fetch` is a bare yield.
    #
    # What the live `Bibliography.get` path gets, and the default everywhere, so
    # runtime behaviour and runtime request count are byte-identical to what
    # they were before the cache existed and no state survives a lookup. Only
    # `DataParserT`, walking one corpus of 16k rows, injects a real one.
    #
    class NullCache
      def self.instance
        @instance ||= new
      end

      def fetch(_key)
        yield
      end

      def warm(_keys, value)
        value
      end

      def caching?
        false
      end

      def stats
        { hits: 0, misses: 0, entries: 0, evictions: 0 }
      end
    end
  end
end
