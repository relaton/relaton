# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Bibitem#edition singular tolerance" do
  # THE LAW: a bibitem has exactly one edition — no published corpus
  # document anywhere carries two (relaton-data-iso: 0 of 61,635). A second
  # <edition> is wrong output (relaton-db#149: the iso-10303 collection
  # render fused the SMRL library bibdata into part bibitems). The
  # tolerance is a crash guard against that wrong output: it keeps the
  # bibitem's own leading edition instead of aborting the round-trip with
  # CollectionTrueMissingError.
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
