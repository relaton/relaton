# frozen_string_literal: true

RSpec.describe "relaton top-level entry point" do
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

  it "does NOT pull relaton-cli's runtime code via require 'relaton'" do
    # The gem's lib/relaton.rb requires only relaton/db, not relaton/cli.
    # Even if Relaton::Cli is defined as a module shell by some other code
    # path, its runtime classes (Command, ::start) must not be loaded just
    # from `require 'relaton'`.
    expect(defined?(Relaton::Cli::Command)).to be_nil
    expect(Relaton::Cli.respond_to?(:start)).to be(false) if defined?(Relaton::Cli)
  end
end
