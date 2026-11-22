# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Relaton::Render::Iso690::I18n do
  it "loads declarations per language from YAML" do
    expect(described_class.load("en").label("and")).to eq "and"
    expect(described_class.load("fr").label("and")).to eq "et"
  end

  it "declares language-varying punctuation" do
    expect(described_class.load("en").punct).to be_empty
    expect(described_class.load("fr").punct["production_sep"]).to eq " : "
  end

  it "defaults to English for no language" do
    expect(described_class.load(nil).lang).to eq "en"
  end

  it "falls back to English for an undeclared language, keeping the requested one for localization" do
    i18n = nil
    expect { i18n = described_class.load("zz") }
      .to output(/falling back to en/).to_stderr
    expect(i18n.label("and")).to eq "and"
    expect(i18n.lang).to eq "zz"
  end

  # relaton#597: the caller's i18n hash carries a punct subtree (the
  # flavor's isodoc i18n YAML, e.g. metanorma-iso's
  # `punct: biblio-terminator: ""`); it overlays the pack's punct
  it "overlays a caller punct subtree over the language pack" do
    i18n = described_class.load("en")
    i18n.overlay_hash!("edition" => "Aufl.",
                       "punct" => { "biblio-terminator" => "" })
    expect(i18n.punct_fetch("biblio-terminator", ".")).to eq ""
    expect(i18n.label("edition")).to eq "Aufl."
    # string and symbol keys land alike: callers symbolize the hash to
    # varying depths (General#deep_symbolize)
    i18n = described_class.load("en")
    i18n.overlay_hash!(punct: { "biblio-terminator" => "" })
    expect(i18n.punct_fetch("biblio-terminator", ".")).to eq ""
  end
end
