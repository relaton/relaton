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
end
