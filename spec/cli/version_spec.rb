require_relative "spec_helper"

# relaton-cli is a compatibility shell now: its gemspec carries a literal
# version that only needs to sort above the last real standalone release
# (3.0.7), and it pulls the consolidated relaton gem — which ships the CLI
# itself at lib/relaton/cli — as its single runtime dependency. These guard
# against the shell accidentally re-coupling to Relaton::VERSION or
# re-declaring dependencies the relaton gem already provides.
RSpec.describe "relaton-cli compatibility shell" do
  context "the built gemspec" do
    let(:gemspec) do
      path = File.expand_path("../../gems/relaton-cli/relaton-cli.gemspec",
                              __dir__)
      Gem::Specification.load(path)
    end

    it "carries a literal version above the last standalone release" do
      expect(gemspec.version.to_s).to eq("3.1.0")
    end

    it "pulls the relaton gem as its runtime dependency" do
      deps = gemspec.dependencies.map { |d| [d.name, d.requirement.to_s] }
      expect(deps).to eq([["relaton", ">= 3.0.7, < 5"]])
    end

    it "ships only the require shim and metadata files" do
      expect(gemspec.files).to contain_exactly("lib/relaton-cli.rb",
                                               "LICENSE", "CHANGELOG.md")
    end
  end
end
