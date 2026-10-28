# frozen_string_literal: true

require "pubid"

# The v2-dialect migration (parsanol#352): parsanol 1.3.110 made the
# named-tree dialect its default and 1.3.111 shipped the trivia exemption
# (parsanol#355); pubid#614 re-baked the artifacts at it, so plain parses
# are parameter-shaped from 1.3.111 onward. The relaton-data-* crawlers
# bundle relaton and pubid from git with no lock — on 2026-10-27 they
# resolved 1.3.110 and published indexes whose every row was a parse tree:
# no ITU lookup matched (relaton-itu#64). `relaton.gemspec` therefore
# floors parsanol at 1.3.111; this spec guards the floor and the parse it
# protects.
RSpec.describe "parsanol dialect" do
  let(:gemspec) do
    Gem::Specification.load(File.expand_path("../../relaton.gemspec", __dir__))
  end

  it "the gemspec floors parsanol at the trivia-exempt release" do
    requirement = gemspec.dependencies.find { |d| d.name == "parsanol" }&.requirement
    expect(requirement).not_to be_nil
    expect(requirement).to be_satisfied_by(Gem::Version.new("1.3.111"))
    expect(requirement).not_to be_satisfied_by(Gem::Version.new("1.3.109"))
    expect(requirement).not_to be_satisfied_by(Gem::Version.new("1.3.110"))
  end

  it "pubid parses an identifier into plain values" do
    expect(Pubid::Itu.parse("ITU-R TF.2018-0").to_hash).to include(
      "series" => "TF", "number" => "2018", "parts" => ["0"],
    )
  end
end
