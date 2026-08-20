# frozen_string_literal: true

require "relaton/w3c/governor"

RSpec.describe Relaton::W3c::Governor do
  # A virtual clock that the sleeper advances, so cooldown arithmetic is
  # exercised for real while the suite stays instant and deterministic.
  let(:clock) { -> { @now } }
  let(:slept) { [] }
  let(:sleeper) { ->(secs) { slept << secs; @now += secs } }
  let(:no_jitter) { ->(_secs) { 0 } }

  before { @now = Time.at(1_000_000) }

  subject(:governor) do
    described_class.new(base: 60, max: 900, give_up_after: 5,
                        clock: clock, sleeper: sleeper, jitter: no_jitter)
  end

  describe "#wait" do
    it "does not sleep when nothing has been throttled" do
      expect(governor.wait).to eq 0.0
      expect(slept).to be_empty
    end

    it "sleeps out the remaining cooldown after a throttle" do
      governor.throttled!
      expect(governor.wait).to eq 60
      expect(slept).to eq [60]
    end

    it "does not sleep again once the cooldown has elapsed" do
      governor.throttled!
      governor.wait
      expect(governor.wait).to eq 0.0
      expect(slept).to eq [60]
    end

    it "sleeps only the remainder for a worker that arrives late" do
      governor.throttled!
      @now += 20
      expect(governor.wait).to eq 40
    end

    it "adds jitter so workers do not resume in lockstep" do
      gov = described_class.new(base: 60, max: 900, give_up_after: 5, clock: clock,
                                sleeper: sleeper, jitter: ->(secs) { secs * 0.1 })
      gov.throttled!
      expect(gov.wait).to be_within(0.001).of(66.0)
    end

    it "returns immediately once the crawl has given up" do
      # Nothing is left to wait for, so an in-flight worker must not stall the
      # shutdown for the remaining (up to 15 minute) cooldown.
      5.times { governor.throttled!; @now += 1000 }
      expect(governor).to be_exhausted
      slept.clear
      expect(governor.wait).to eq 0.0
      expect(slept).to be_empty
    end
  end

  describe "#throttled!" do
    it "escalates the cooldown on each new round, capped at max" do
      # give_up_after is raised out of the way so this isolates the ladder;
      # #wait short-circuits to 0 once the crawl has given up.
      gov = described_class.new(base: 60, max: 900, give_up_after: 100,
                                clock: clock, sleeper: sleeper, jitter: no_jitter)
      observed = 6.times.map { gov.throttled!; gov.wait }
      expect(observed).to eq [60.0, 120.0, 240.0, 480.0, 900.0, 900.0]
    end

    it "does not escalate for throttles inside an open cooldown" do
      # Four workers tripping the same limiter is one round, not four: it must
      # not fast-forward the escalation ladder or the give-up counter.
      4.times { governor.throttled! }
      expect(governor.wait).to eq 60
      expect(governor.throttle_rounds).to eq 1
    end

    it "counts every throttle event for reporting" do
      4.times { governor.throttled! }
      expect(governor.throttle_count).to eq 4
    end

    it "reports whether the crawl should give up" do
      expect(4.times.map { governor.throttled!.tap { @now += 1000 } })
        .to eq [false, false, false, false]
      expect(governor.throttled!).to be true
    end

    context "with a Retry-After hint" do
      it "raises the cooldown floor when the server asks for longer" do
        governor.throttled!(retry_after: 300)
        expect(governor.wait).to eq 300
      end

      it "keeps its own escalation when Retry-After is shorter" do
        governor.throttled!(retry_after: 5)
        expect(governor.wait).to eq 60
      end

      it "caps a hostile Retry-After at max" do
        governor.throttled!(retry_after: 86_400)
        expect(governor.wait).to eq 900
      end

      it "extends an open cooldown when a later hint asks for longer" do
        governor.throttled!
        governor.throttled!(retry_after: 300)
        expect(governor.wait).to eq 300
      end

      it "holds back a worker already sleeping when the cooldown is extended" do
        # Without this, an extension only binds threads that enter #wait after
        # it — everyone already asleep wakes on the stale deadline and re-trips
        # the limiter, which is the whole failure mode being extended away.
        governor.throttled!
        extending = ->(secs) { slept << secs; @now += secs }
        gov_sleeper = lambda do |secs|
          extending.call(secs)
          # A second worker's 429 lands while this one is asleep.
          governor.throttled!(retry_after: 300) if slept.size == 1
        end
        allow(governor).to receive(:sleep) # guard against a real sleep
        governor.instance_variable_set(:@sleeper, gov_sleeper)

        expect(governor.wait).to eq 360 # 60 slept, then the extension's 300
      end
    end
  end

  describe "#succeeded!" do
    it "clears the cooldown and the give-up counter" do
      4.times { governor.throttled!; @now += 1000 }
      governor.succeeded!
      expect(governor.wait).to eq 0.0
      expect(governor).not_to be_exhausted
    end

    it "decays the penalty rather than resetting it, so a flapping limiter still escalates" do
      3.times { governor.throttled!; @now += 1000 } # ladder at 240
      governor.succeeded!
      governor.throttled!
      expect(governor.wait).to eq 240 # 240 -> decayed to 120 -> escalated back to 240
    end
  end

  describe "#exhausted?" do
    it "is false before give_up_after consecutive rounds" do
      4.times { governor.throttled!; @now += 1000 }
      expect(governor).not_to be_exhausted
    end

    it "is true after give_up_after consecutive rounds with no success" do
      5.times { governor.throttled!; @now += 1000 }
      expect(governor).to be_exhausted
    end

    it "latches, so a straggler success cannot un-abandon the crawl" do
      # The producer stops paginating the moment this goes true. If a worker
      # still in flight could clear it, the crawl would go on to save the
      # truncated index it had already decided to throw away.
      5.times { governor.throttled!; @now += 1000 }
      governor.succeeded!
      expect(governor).to be_exhausted
    end

    it "is cleared by #reset! for the next crawl" do
      5.times { governor.throttled!; @now += 1000 }
      governor.reset!
      expect(governor).not_to be_exhausted
      expect(governor.throttle_count).to eq 0
    end
  end

  describe ".retry_after" do
    # lutaml-hal >= 0.2.5 carries the HTTP context as a real constructor kwarg
    # on Lutaml::Hal::Error, shaped by Client#response_context.
    def error_with(headers, klass = Lutaml::Hal::TooManyRequestsError)
      klass.new("Status: 429", response: { status: 429, headers: headers })
    end

    it "reads an integer Retry-After" do
      expect(described_class.retry_after(error_with("retry-after" => "120"))).to eq 120
    end

    it "is case-insensitive about the header name" do
      expect(described_class.retry_after(error_with("Retry-After" => "120"))).to eq 120
    end

    it "reads it off a 403 as well, since that is a W3C throttle" do
      expect(described_class.retry_after(
               error_with({ "retry-after" => "90" }, Lutaml::Hal::ForbiddenError),
             )).to eq 90
    end

    it "parses an HTTP-date into a delta" do
      # RFC 9110 permits a date. It must be parsed, not digit-scanned — that
      # would pick up the day-of-month and back off for a wildly wrong time.
      future = (Time.now + 120).httpdate
      expect(described_class.retry_after(error_with("retry-after" => future)))
        .to be_within(2).of(120)
    end

    it "treats a past HTTP-date as no extra delay" do
      past = (Time.now - 3600).httpdate
      expect(described_class.retry_after(error_with("retry-after" => past))).to eq 0
    end

    it "returns nil for an unparseable value" do
      expect(described_class.retry_after(error_with("retry-after" => "soon"))).to be_nil
    end

    it "returns nil when the header is absent" do
      expect(described_class.retry_after(error_with({}))).to be_nil
    end

    it "returns nil for a locally raised error with no response context" do
      expect(described_class.retry_after(Lutaml::Hal::Error.new("boom"))).to be_nil
      expect(described_class.retry_after(StandardError.new("boom"))).to be_nil
    end
  end

  describe "THROTTLE_ERRORS" do
    it "covers both of api.w3.org's rate-limit signals" do
      expect(described_class::THROTTLE_ERRORS)
        .to contain_exactly(Lutaml::Hal::TooManyRequestsError, Lutaml::Hal::ForbiddenError)
    end
  end

  describe "defaults" do
    around do |ex|
      orig = ENV.values_at("RELATON_W3C_THROTTLE_BASE", "RELATON_W3C_THROTTLE_MAX",
                           "RELATON_W3C_THROTTLE_GIVEUP")
      ex.run
      %w[RELATON_W3C_THROTTLE_BASE RELATON_W3C_THROTTLE_MAX RELATON_W3C_THROTTLE_GIVEUP]
        .each_with_index { |k, i| orig[i].nil? ? ENV.delete(k) : ENV[k] = orig[i] }
    end

    it "falls back to the constants when the env vars are unset" do
      %w[RELATON_W3C_THROTTLE_BASE RELATON_W3C_THROTTLE_MAX RELATON_W3C_THROTTLE_GIVEUP].each { |k| ENV.delete(k) }
      gov = described_class.new
      expect(gov.base).to eq described_class::BASE_COOLDOWN
      expect(gov.max).to eq described_class::MAX_COOLDOWN
      expect(gov.give_up_after).to eq described_class::GIVE_UP_AFTER
    end

    it "reads overrides from the environment" do
      ENV["RELATON_W3C_THROTTLE_BASE"] = "5"
      ENV["RELATON_W3C_THROTTLE_MAX"] = "50"
      ENV["RELATON_W3C_THROTTLE_GIVEUP"] = "2"
      gov = described_class.new
      expect([gov.base, gov.max, gov.give_up_after]).to eq [5, 50, 2]
    end

    it "ignores non-positive overrides" do
      ENV["RELATON_W3C_THROTTLE_BASE"] = "0"
      expect(described_class.new.base).to eq described_class::BASE_COOLDOWN
    end
  end

  describe "thread safety" do
    it "keeps its counters consistent under concurrent use" do
      gov = described_class.new(base: 0.001, max: 0.002, give_up_after: 1_000_000)
      threads = Array.new(8) do
        Thread.new { 50.times { gov.throttled!; gov.wait; gov.succeeded! } }
      end
      threads.each(&:join)
      expect(gov.throttle_count).to eq 400
    end
  end
end
