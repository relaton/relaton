require "relaton/itu/family_cache"
require "timeout"

# The ITU-T cross-row cache. Pure unit — no HTTP, no cassette. What it has to
# get right is (a) one request per family instead of one per edition, (b) never
# serving one recommendation another's data, and (c) never blocking the pool.
RSpec.describe Relaton::Itu::FamilyCache do
  subject(:cache) { described_class.new }

  it "computes once and serves the rest" do
    calls = 0
    3.times { cache.fetch(%i[editions 1]) { calls += 1 } }
    expect(calls).to eq 1
    expect(cache.stats).to include(hits: 2, misses: 1)
  end

  it "keeps different keys apart" do
    expect(cache.fetch(%i[editions 1]) { :a }).to eq :a
    expect(cache.fetch(%i[editions 2]) { :b }).to eq :b
    expect(cache.fetch(%i[supplements 1]) { :c }).to eq :c
  end

  it "runs the block once when two workers race the same key" do
    started = Queue.new
    release = Queue.new
    calls = Queue.new
    threads = 2.times.map do
      Thread.new do
        cache.fetch(%i[editions 7]) do
          calls << :call
          started << :in
          release.pop
          :value
        end
      end
    end
    started.pop
    release << :go
    Timeout.timeout(10) { expect(threads.map(&:value)).to eq %i[value value] }
    expect(calls.size).to eq 1
  end

  it "does not block one key's fetch behind another's" do
    # If the table lock were held across the block, eight workers would collapse
    # onto one connection's latency.
    in_first = Queue.new
    release = Queue.new
    slow = Thread.new { cache.fetch(%i[editions 1]) { in_first << :in; release.pop; :a } }
    in_first.pop
    Timeout.timeout(5) { expect(cache.fetch(%i[editions 2]) { :b }).to eq :b }
    release << :go
    slow.join
  end

  it "does not cache a failure, so the next sibling retries" do
    expect { cache.fetch(%i[workgroup 1]) { raise IOError, "boom" } }.to raise_error IOError
    expect(cache.fetch(%i[workgroup 1]) { :recovered }).to eq :recovered
  end

  describe "#warm" do
    it "publishes one response under every sibling it answers for" do
      # The self-warming property: getRecEditions names all 21 siblings, so one
      # request covers the family without any name parsing.
      rows = [{ "idrec" => 16_818 }, { "idrec" => 14_659 }]
      cache.warm([%i[editions 14659]], rows)
      expect(cache.fetch(%i[editions 14659]) { raise "must not fetch" }).to eq rows
    end

    it "leaves an already-computed entry alone" do
      cache.fetch(%i[editions 1]) { :original }
      cache.warm([%i[editions 1]], :replacement)
      expect(cache.fetch(%i[editions 1]) { :nope }).to eq :original
    end
  end

  describe "bounded size" do
    subject(:cache) { described_class.new max_entries: 2 }

    it "evicts the least recently used and never exceeds the cap" do
      cache.fetch(:a) { 1 }
      cache.fetch(:b) { 2 }
      cache.fetch(:c) { 3 }
      expect(cache.stats[:entries]).to eq 2
      expect(cache.stats[:evictions]).to eq 1
      calls = 0
      cache.fetch(:a) { calls += 1 }
      expect(calls).to eq 1 # :a was evicted, so it is recomputed
    end
  end
end

RSpec.describe Relaton::Itu::NullCache do
  subject(:cache) { described_class.instance }

  it "calls the block every time, so the runtime path is unchanged" do
    calls = 0
    3.times { cache.fetch(:k) { calls += 1 } }
    expect(calls).to eq 3
  end

  it "warms nothing and reports nothing" do
    expect(cache.warm([:a], :v)).to eq :v
    expect(cache.stats.values).to all eq 0
  end
end
