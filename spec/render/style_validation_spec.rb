require_relative "spec_helper"
require "yaml"

# CitationStyle instances are checked against the structural requirements
# of the relaton-models LML (CitationStyle et al.). The full JSON Schema
# validation runs in the models repo (rake fixtures:schema); this spec
# guards the same invariants so a malformed instance cannot ship.
RSpec.describe "CitationStyle instance" do
  let(:instance) do
    YAML.load_file(File.expand_path("fixtures/citation/iso-690.yml", __dir__))
  end

  it "declares itself as a CitationStyle" do
    expect(instance["class"]).to eq("CitationStyle")
  end

  it "carries a name" do
    expect(instance["name"]).to be_a(String)
    expect(instance["name"]).not_to be_empty
  end

  it "has a citation scheme with system, name form, locale, and disambiguation" do
    scheme = instance["scheme"]
    expect(scheme).to include("class" => "CitationScheme")
    expect(scheme["system"]).to be_a(String)
    expect(scheme["system"]).not_to be_empty
    expect(scheme["nameForm"]).to include("initials" => false) # the conformance corpus renders full given names
    expect(scheme["nameForm"]["givenNameFirst"]).to be(false)
    # locale is a per-style OVERRIDE of the language packs, deliberately
    # absent here: re-declaring pack strings would override every language
    expect(scheme).not_to have_key("locale")
    expect(scheme["disambiguation"]).to include("yearSuffix" => a_string_matching(/\S/))
  end

  it "has templates for citation and reference forms" do
    # the citation form is in-text: the principal creator's surname, not
    # the full creator element
    expect(instance.dig("templates", "citation")).to include("{{surname}}")
    expect(instance.dig("templates", "reference")).to include("{{title}}")
  end

  it "declares per-type template overrides" do
    expect(instance["perType"]).to be_an(Array)
    instance["perType"].each do |tt|
      expect(tt).to include("type", "template")
    end
  end

  it "declares sort keys" do
    expect(instance["sortKey"]).to be_an(Array)
    instance["sortKey"].each { |r| expect(r).to include("attribute") }
  end
end
