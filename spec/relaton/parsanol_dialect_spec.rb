# frozen_string_literal: true

require "pubid"

# The numeric capture editions (parsanol ruby#361, ruby#357's axis):
# 1.3.114 records the capture edition as the integer 2 in the artifact
# envelope and carries the edition-2 whitespace-class glue fix, and
# pubid 2.0.0.pre.alpha.65 re-bakes every artifact at it and requires
# >= 1.3.114. parsanol 1.3.120 removes the pre-1.3.113 `mode` grammar
# header alias, and pubid 2.0.3 re-bakes the iso artifact at edition 2
# for that line. `relaton.gemspec` therefore floors parsanol at
# 1.3.121 with pubid at 2.0.3; this spec guards the floors and the
# parses they protect.
RSpec.describe "parsanol dialect" do
  let(:gemspec) do
    Gem::Specification.load(File.expand_path("../../relaton.gemspec", __dir__))
  end

  it "the gemspec floors parsanol at the mode-alias-removal release" do
    requirement = gemspec.dependencies.find { |d| d.name == "parsanol" }&.requirement
    expect(requirement).not_to be_nil
    expect(requirement).to be_satisfied_by(Gem::Version.new("1.3.121"))
    expect(requirement).not_to be_satisfied_by(Gem::Version.new("1.3.120"))
    expect(requirement).not_to be_satisfied_by(Gem::Version.new("1.3.112"))
  end

  it "the gemspec floors pubid at the edition-2 iso artifact release" do
    requirement = gemspec.dependencies.find { |d| d.name == "pubid" }&.requirement
    expect(requirement).not_to be_nil
    expect(requirement).to be_satisfied_by(Gem::Version.new("2.0.3"))
    expect(requirement).not_to be_satisfied_by(Gem::Version.new("2.0.2"))
  end

  it "pubid parses an identifier into plain values" do
    expect(Pubid::Itu.parse("ITU-R TF.2018-0").to_hash).to include(
      "series" => "TF", "number" => "2018", "parts" => ["0"],
    )
  end
end
