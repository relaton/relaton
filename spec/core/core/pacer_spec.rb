require "relaton/core/pacer"

# The shared request pacer (relaton-data-itu's crawler hit the 6 h Actions cap).
#
# The unit under test is arithmetic, not HTTP: `clock:` and `sleeper:` are
# injected so the whole ladder is exercised without a wall-clock wait. The one
# property that matters is that N workers between them start **at most one
# request per gap** — a per-worker pacer (Relaton::Cie::DataFetcher::Pacing)
# gives N requests per gap, which is exactly what this must not do.
RSpec.describe Relaton::Core::Pacer do
  # A controllable monotonic clock. The sleeper advances it, mirroring what a
  # real `sleep` does, so the reservations and the elapsed time stay consistent.
  let(:now) { [0.0] }
  let(:slept) { [] }
  let(:clock) { -> { now[0] } }
  let(:sleeper) { ->(secs) { slept << secs; now[0] += secs } }

  subject(:pacer) { described_class.new gap: 1.0, clock: clock, sleeper: sleeper }

  it "lets the first request go immediately" do
    expect(pacer.wait).to eq 0.0
    expect(slept).to be_empty
  end

  it "spaces successive request starts by the gap" do
    pacer.wait
    expect(pacer.wait).to be_within(1e-9).of(1.0)
    expect(pacer.wait).to be_within(1e-9).of(1.0)
    expect(now[0]).to be_within(1e-9).of(2.0)
  end

  it "counts the server's own latency toward the gap instead of adding to it" do
    pacer.wait          # request 1 starts at t=0
    now[0] += 1.5       # ...and takes 1.5 s, which is longer than the gap
    expect(pacer.wait).to eq 0.0 # so request 2 goes straight out
    expect(slept).to be_empty
  end

  it "sleeps only the remainder when the request was shorter than the gap" do
    pacer.wait
    now[0] += 0.4
    expect(pacer.wait).to be_within(1e-9).of(0.6)
  end

  it "does not let an idle period bank up slots" do
    pacer.wait
    now[0] += 60.0 # a long stall elsewhere in the crawl
    expect(pacer.wait).to eq 0.0
    expect(pacer.wait).to be_within(1e-9).of(1.0) # and paces normally again
  end

  it "never sleeps when the gap is zero" do
    free = described_class.new gap: 0, clock: clock, sleeper: sleeper
    5.times { expect(free.wait).to eq 0.0 }
    expect(slept).to be_empty
  end

  it "treats a negative gap as zero" do
    expect(described_class.new(gap: -5).gap).to eq 0.0
  end

  context "under a worker pool" do
    # The real thing: a genuinely concurrent reservation must still yield one
    # slot per gap. Uses the real clock and a no-op sleeper so the assertion is
    # about the *reserved instants*, not about how long the suite takes.
    it "hands out one slot per gap across threads, with no two the same" do
      reserved = Queue.new
      t = 0.0
      pool_pacer = described_class.new(
        gap: 1.0,
        clock: -> { t },
        # A worker "sleeping" does not advance the shared clock here; that keeps
        # the reservations themselves under test.
        sleeper: ->(secs) { reserved << secs },
      )
      threads = 8.times.map { Thread.new { pool_pacer.wait } }
      threads.each(&:join)

      waits = []
      waits << reserved.pop until reserved.empty?
      # 8 workers, gap 1.0, clock frozen at 0: one goes now, the rest are
      # spaced 1..7 s out. Sorted because completion order is nondeterministic.
      expect(waits.sort).to eq [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0]
    end

    it "does not hold the lock across the sleep" do
      # One worker is parked inside its sleep; another must still be able to
      # reserve. If the mutex were held across the sleep this join would time
      # out. The gate only blocks the FIRST sleeper, so the second worker runs
      # to completion instead of parking behind the same gate.
      entered = Queue.new
      release = Queue.new
      first = true
      slow = described_class.new(
        gap: 1.0,
        clock: clock,
        sleeper: lambda { |_secs|
          next unless first

          first = false
          entered << :in
          release.pop
        },
      )
      slow.wait                      # claims t=0, due immediately, no sleep
      parked = Thread.new { slow.wait }  # claims t=1, then parks in the sleeper
      entered.pop                    # ...confirmed parked
      other = Thread.new { slow.wait }   # must still reserve t=2
      expect(other.join(5)).to be_truthy
      release << :go
      parked.join
    end
  end
# The rollback knob. `:fixed` reproduces the pre-pacer crawler exactly: sleep
# the whole gap before every request, whatever else is happening, so the host
# sees one request per (gap + its own latency).
context "mode: :fixed" do
  subject(:fixed) { described_class.new gap: 1.0, mode: :fixed, clock: clock, sleeper: sleeper }

  it "sleeps the full gap before every request, including the first" do
    expect(fixed.wait).to be_within(1e-9).of(1.0)
    expect(fixed.wait).to be_within(1e-9).of(1.0)
  end

  it "ignores elapsed time, so latency is added to the delay rather than absorbed" do
    fixed.wait
    now[0] += 30.0
    expect(fixed.wait).to be_within(1e-9).of(1.0)
  end

  it "still does nothing when the gap is zero" do
    expect(described_class.new(gap: 0, mode: :fixed, clock: clock, sleeper: sleeper).wait).to eq 0.0
  end
end

it "counts what it did, for the run summary" do
  pacer.wait
  now[0] += 0.25
  pacer.wait
  expect(pacer.requests).to eq 2
  expect(pacer.slept).to be_within(1e-9).of(0.75)
end

end
