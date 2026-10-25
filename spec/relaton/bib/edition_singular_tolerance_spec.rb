# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Bibitem#edition singular tolerance" do
  # Upstream corpus documents carry more than one <edition> in a bibitem
  # (relaton-db#149): the collection-count validation used to abort the
  # whole XML round-trip with CollectionTrueMissingError. The attribute
  # tolerates the over-ingest and keeps the leading value.
  subject(:item) do
    Relaton::Bib::Bibitem.from_xml(<<~X)
      <bibitem type="book">
        <title row="main">Multi-edition reference</title>
        <docidentifier>ISO 1</docidentifier>
        <edition>1</edition>
        <edition>2</edition>
        <date type="published"><on>2026</on></date>
      </bibitem>
    X
  end

  it "parses without CollectionTrueMissingError" do
    expect { item }.not_to raise_error
  end

  it "keeps the first edition" do
    expect(item.edition.content).to eq("1")
  end

  it "round-trips to XML" do
    expect { item.to_xml }.not_to raise_error
    expect(item.to_xml).not_to include("CollectionTrue")
  end
end
