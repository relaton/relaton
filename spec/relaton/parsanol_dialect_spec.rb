# frozen_string_literal: true

require "pubid"

# The dialect axis (parsanol ruby#357): 1.3.112 consolidates the capture
# dialect to ONE axis — the artifact envelope records `edition`
# ("v1"/"v2") in place of the mode + emission pair — and pubid#617
# re-bakes every artifact at it and floors the gemspec there. A runtime
# older than the release cannot read those artifacts (it re-parses the
# embedded grammar source, where `edition` is an unknown keyword).
# `relaton.gemspec` therefore floors parsanol at 1.3.112; this spec
# guards the floor and the parse it protects.
RSpec.describe "parsanol dialect" do
  let(:gemspec) do
    Gem::Specification.load(File.expand_path("../../relaton.gemspec", __dir__))
  end

  it "the gemspec floors parsanol at the edition-axis release" do
    requirement = gemspec.dependencies.find { |d| d.name == "parsanol" }&.requirement
    expect(requirement).not_to be_nil
    expect(requirement).to be_satisfied_by(Gem::Version.new("1.3.112"))
    expect(requirement).not_to be_satisfied_by(Gem::Version.new("1.3.109"))
    expect(requirement).not_to be_satisfied_by(Gem::Version.new("1.3.111"))
  end

  it "pubid parses an identifier into plain values" do
    expect(Pubid::Itu.parse("ITU-R TF.2018-0").to_hash).to include(
      "series" => "TF", "number" => "2018", "parts" => ["0"],
    )
  end
end
