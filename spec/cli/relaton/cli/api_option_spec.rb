# `--api` / `--no-api` (relaton#535): the CLI's switch for the
# api.relaton.org tier, which a program sets with
# `Relaton::Db.configuration.use_api` and a shell with RELATON_USE_API.
require "relaton/db"
require "relaton/cli"

RSpec.describe "relaton fetch --api" do
  let(:db) { double "db" }

  def use_api = Relaton::Db.configuration.use_api

  # The tier's state when Db#fetch runs; the fetch answers nothing, so no
  # output and no collection file is written.
  def run(*args, command: "fetch")
    seen = :not_called
    allow(db).to receive(:fetch) do |*_, **opts|
      seen = use_api
      @opts = opts
      nil
    end
    Relaton::Cli::Command.start(
      if command == "fetch" then ["fetch", "ISO 2146", *args]
      else
        ["collection", "fetch", "ISO 2146", "-t", "ISO", "-d", "spec/fixtures",
         "-c", "sample-collection.yaml", *args]
      end,
    )
    seen
  end

  around do |ex|
    old = ENV.fetch("RELATON_USE_API", nil)
    Relaton::Db.instance_variable_set :@configuration, nil
    ex.run
  ensure
    old ? ENV["RELATON_USE_API"] = old : ENV.delete("RELATON_USE_API")
    Relaton::Db.instance_variable_set :@configuration, nil
  end

  before do
    allow(Relaton::Cli).to receive(:relaton).and_return db
    allow(Relaton).to receive(:db).and_return db
  end

  %w[fetch collection].each do |command|
    context "relaton #{command} fetch" do
      it "turns the tier on with --api" do
        expect(run("--api", command: command)).to be true
      end

      it "turns the tier off with --no-api over RELATON_USE_API" do
        ENV["RELATON_USE_API"] = "1"
        Relaton::Db.instance_variable_set :@configuration, nil
        expect(run("--no-api", command: command)).to be false
      end

      it "keeps RELATON_USE_API without a flag" do
        ENV["RELATON_USE_API"] = "1"
        Relaton::Db.instance_variable_set :@configuration, nil
        expect(run(command: command)).to be true
      end

      it "keeps the tier off by default" do
        ENV.delete "RELATON_USE_API"
        expect(run(command: command)).to be false
      end

      it "sets the tier for this run only" do
        ENV.delete "RELATON_USE_API"
        run("--api", command: command)
        expect(use_api).to be false
      end

      it "passes no api option to the fetch" do
        run("--api", command: command)
        expect(@opts).not_to include(:api)
      end
    end
  end
end
