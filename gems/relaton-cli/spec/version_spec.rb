require "spec_helper"

# relaton-cli is released in lockstep with the combined `relaton` gem from this
# repo. Both its runtime version constant and its gemspec (version + relaton
# dependency) must derive from the single source of truth, Relaton::VERSION, so
# that `gem bump` on the one root version file re-stamps both gems. These guard
# against the two silently drifting apart again.
RSpec.describe "relaton-cli version sync" do
  it "reports the same runtime version as relaton" do
    expect(Relaton::Cli::VERSION).to eq(Relaton::VERSION)
  end

  context "the built gemspec" do
    let(:gemspec) do
      path = File.expand_path("../relaton-cli.gemspec", __dir__)
      Gem::Specification.load(path)
    end

    it "takes its version from Relaton::VERSION" do
      expect(gemspec.version.to_s).to eq(Relaton::VERSION)
    end

    it "pins relaton to exactly Relaton::VERSION" do
      dep = gemspec.dependencies.find { |d| d.name == "relaton" }
      expect(dep).not_to be_nil
      expect(dep.requirement.to_s).to eq("= #{Relaton::VERSION}")
    end
  end
end
