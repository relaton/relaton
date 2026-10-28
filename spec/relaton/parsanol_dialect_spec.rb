# frozen_string_literal: true

require "pubid"

# parsanol 1.3.110 made the v2 named-tree dialect its default: every uncaptured
# rule reference surfaces as a capture, and pubid folds the captures into its
# parameters. A digit run then parses as a per-atom list, so
# `Pubid::Itu.parse("ITU-R TF.2018-0").to_hash` gives
# `"number" => "[{digit: \"2\"}, {digit: \"0\"}, …]"` (1.3.111 too).
#
# The Gemfile pin keeps this repo's own bundle on 1.3.109, but a Gemfile pin
# does not reach a dependent bundle. The relaton-data-* crawlers bundle relaton
# and pubid from git with no lock, so on 2026-10-27 they resolved 1.3.111 and
# published indexes whose every row was a parse tree: no ITU lookup matched
# (relaton-itu#64). `relaton.gemspec` therefore caps parsanol; this spec
# guards the cap and the parse it protects.
RSpec.describe "parsanol dialect" do
  let(:gemspec) do
    Gem::Specification.load(File.expand_path("../../relaton.gemspec", __dir__))
  end

  it "the gemspec rejects the v2-dialect parsanol releases" do
    requirement = gemspec.dependencies.find { |d| d.name == "parsanol" }&.requirement
    expect(requirement).not_to be_nil
    expect(requirement).to be_satisfied_by(Gem::Version.new("1.3.109"))
    expect(requirement).not_to be_satisfied_by(Gem::Version.new("1.3.110"))
  end

  it "pubid parses an identifier into plain values" do
    expect(Pubid::Itu.parse("ITU-R TF.2018-0").to_hash).to include(
      "series" => "TF", "number" => "2018", "parts" => ["0"],
    )
  end
end
