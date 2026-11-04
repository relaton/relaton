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
end
