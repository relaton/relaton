# frozen_string_literal: true

require "spec_helper"

# relaton#621: `vocab` was declared singular while every source stores an
# array of {content:} entries; the array was swallowed into the scalar
# content and to_yaml emitted LocalizedString object inspects.
RSpec.describe "Bib::Keyword serialization" do
  it "declares vocab as a collection" do
    attr = Relaton::Bib::Keyword.attributes[:vocab]
    expect(attr.options[:collection]).not_to be(false)
    expect(attr.options[:collection]).to be_truthy
  end

  it "round-trips vocab arrays" do
    item = Relaton::Bib::Item.from_yaml(<<~YAML)
      ---
      id: K
      title:
      - content: T
      docidentifier:
      - content: K 1
        type: BIPM
        primary: true
      keyword:
      - vocab:
        - content: Keyword
      - vocab:
        - content: Key Word
    YAML
    out = YAML.safe_load(item.to_yaml)
    vocabs = out["keyword"].map { |k| k["vocab"] }
    expect(vocabs).to eq([[{ "content" => "Keyword" }],
                          [{ "content" => "Key Word" }]])
  end
end
