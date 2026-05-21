# frozen_string_literal: true

RSpec.describe Relaton do
  it "has a version" do
    expect(Relaton::VERSION).to be_a(String)
  end

  it "loads Relaton::Db via require 'relaton'" do
    expect(defined?(Relaton::Db)).to eq("constant")
    expect(Relaton::Db).to be_a(Class)
  end

  it "exposes Relaton::Db::Registry" do
    expect(defined?(Relaton::Db::Registry)).to eq("constant")
  end

  it "does NOT auto-require Relaton::Cli (CLI is opt-in)" do
    # Users must `require 'relaton/cli'` explicitly. The meta-gem
    # intentionally does not pull it in.
    expect(defined?(Relaton::Cli)).to be_nil
  end
end
