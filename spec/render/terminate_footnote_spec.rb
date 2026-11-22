# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Relaton::Render::General do
  it "closes the sentence before the footnote" do
    r = described_class.new(language: "en")
    expect(r.terminate_reference("Author. Title<fn><p>x</p></fn>"))
      .to eq "Author. Title.<fn><p>x</p></fn>"
  end

  it "no doubled stop when the sentence already closed" do
    r = described_class.new(language: "en")
    expect(r.terminate_reference("Author. Title 2025. <fn><p>x</p></fn>"))
      .to eq "Author. Title 2025.<fn><p>x</p></fn>"
  end

  it "a trailing span takes no footnote treatment" do
    r = described_class.new(language: "en")
    expect(r.terminate_reference("<span class='stddocTitle'>T</span>"))
      .to eq "<span class='stddocTitle'>T</span>."
  end

  # relaton#597: the bibliography terminator is the caller i18n hash's
  # `punct.biblio-terminator` declaration, defaulting to "."; a flavor
  # declaring "" (metanorma-iso since metanorma-jis#388) suppresses it
  it "terminates with the default period absent a punct declaration" do
    r = described_class.new(language: "en", i18nhash: {})
    expect(r.terminate_reference("Title")).to eq "Title."
  end

  it "suppresses the terminator on an empty biblio-terminator" do
    r = described_class.new(
      language: "en",
      i18nhash: { "punct" => { "biblio-terminator" => "" } },
    )
    expect(r.terminate_reference("Title")).to eq "Title"
    expect(r.terminate_reference("Title<fn><p>x</p></fn>"))
      .to eq "Title<fn><p>x</p></fn>"
  end

  it "terminates with the declared biblio-terminator string" do
    r = described_class.new(
      language: "en",
      i18nhash: { "punct" => { "biblio-terminator" => "。" } },
    )
    expect(r.terminate_reference("Title。")).to eq "Title。"
    expect(r.terminate_reference("Title")).to eq "Title。"
  end
end
