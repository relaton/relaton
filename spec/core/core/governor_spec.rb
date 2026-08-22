require "relaton/core/governor"

# Only what became CORE-owned when the governor was promoted out of
# Relaton::W3c. The ladder's full behaviour is exercised by
# spec/w3c/relaton/w3c/governor_spec.rb, which still runs against the subclass
# and must keep passing unedited — that is the promotion's acceptance test.
RSpec.describe Relaton::Core::Governor do
  let(:now) { [Time.at(0)] }
  let(:clock) { -> { now[0] } }
  let(:slept) { [] }
  let(:sleeper) { ->(secs) { slept << secs; now[0] += secs } }

  def governor(**kwargs)
    described_class.new(clock: clock, sleeper: sleeper, jitter: ->(_s) { 0 }, **kwargs)
  end

  it "ships no throttle errors of its own" do
    expect(described_class::THROTTLE_ERRORS).to be_empty
    expect(described_class.throttle?(StandardError.new)).to be false
  end

  it "recognises whatever error classes a subclass declares" do
    # const_set, not a constant assignment in the block: a block is not a class
    # body, so `THROTTLE_ERRORS = ...` there would define it on Object.
    flavor = Class.new(described_class)
    flavor.const_set :THROTTLE_ERRORS, [ArgumentError].freeze
    expect(flavor.throttle?(ArgumentError.new)).to be true
    expect(flavor.throttle?(TypeError.new)).to be false
  end

  it "defaults its env prefix, and lets a caller override it" do
    expect(governor.env_prefix).to eq "RELATON"
    expect(governor(env_prefix: "RELATON_ITU").env_prefix).to eq "RELATON_ITU"
  end

  it "reads its durations from the prefixed env vars" do
    ENV["RELATON_FLAVOR_THROTTLE_BASE"] = "7"
    ENV["RELATON_FLAVOR_THROTTLE_MAX"] = "70"
    ENV["RELATON_FLAVOR_THROTTLE_GIVEUP"] = "2"
    g = governor(env_prefix: "RELATON_FLAVOR")
    expect([g.base, g.max, g.give_up_after]).to eq [7, 70, 2]
  ensure
    %w[BASE MAX GIVEUP].each { |s| ENV.delete "RELATON_FLAVOR_THROTTLE_#{s}" }
  end

  it "ignores another prefix's knobs, so two flavors cannot share a ladder" do
    ENV["RELATON_W3C_THROTTLE_BASE"] = "999"
    expect(governor(env_prefix: "RELATON_ITU").base).to eq described_class::BASE_COOLDOWN
  ensure
    ENV.delete "RELATON_W3C_THROTTLE_BASE"
  end

  it "lets a subclass retune the ladder through the constants" do
    flavor = Class.new(described_class)
    { BASE_COOLDOWN: 5, MAX_COOLDOWN: 20, GIVE_UP_AFTER: 2,
      ENV_PREFIX: "RELATON_FLAVOR" }.each { |k, v| flavor.const_set k, v }
    g = flavor.new(clock: clock, sleeper: sleeper, jitter: ->(_s) { 0 })
    expect([g.base, g.max, g.give_up_after]).to eq [5, 20, 2]

    g.throttled!                    # round 1 -> 5 s
    expect(g.wait).to eq 5
    g.throttled!                    # round 2 -> 10 s, and give_up_after is 2
    expect(g.exhausted?).to be true
  end

  it "escalates per round and caps at max" do
    g = governor(base: 10, max: 25, give_up_after: 99)
    g.throttled!
    expect(g.wait).to eq 10
    g.throttled!
    expect(g.wait).to eq 20
    g.throttled!
    expect(g.wait).to eq 25 # capped, not 40
  end

  it "decays the penalty on success rather than resetting it" do
    g = governor(base: 10, max: 100, give_up_after: 99)
    g.throttled!
    g.wait
    g.throttled!
    g.wait                # penalty is now 20
    g.succeeded!          # decays to 10, not to nil
    expect(g.throttle_rounds).to eq 0
    g.throttled!
    expect(g.wait).to eq 20 # 10 * 2 — the ladder remembers the flapping
  end

  it "latches giving up, so a straggler success cannot resurrect the run" do
    g = governor(base: 1, max: 1, give_up_after: 1)
    g.throttled!
    expect(g.exhausted?).to be true
    g.succeeded!
    expect(g.exhausted?).to be true
    expect(g.wait).to eq 0.0 # and stops blocking, so shutdown is immediate
  end
end
