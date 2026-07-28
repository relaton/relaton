# frozen_string_literal: true

RSpec.describe Relaton::Jcgm::Bibliography do
  it "fetches a meeting record" do
    bib = described_class.get "JCGM 17th Meeting (2012)"
    expect(bib).to be_a(Relaton::Jcgm::ItemData)
    expect(bib.docidentifier.first.content).to eq "JCGM 17th Meeting (2012)"
    expect(bib.ext.doctype.content).to eq "meeting-report"
  end

  it "fetches a meeting with a naive ordinal (11st)" do
    bib = described_class.get "JCGM 11st Meeting (2006)"
    expect(bib.docidentifier.first.content).to eq "JCGM 11st Meeting (2006)"
  end

  it "fetches a guide record" do
    bib = described_class.get "JCGM 200:2012"
    expect(bib).to be_a(Relaton::Jcgm::ItemData)
    expect(bib.docidentifier.first.content).to eq "JCGM 200:2012"
  end

  it "fetches a GUM guide record" do
    bib = described_class.get "JCGM GUM-6:2020"
    expect(bib.docidentifier.first.content).to eq "JCGM GUM-6:2020"
  end

  it "distinguishes editions by year (200:2008 vs 200:2012)" do
    expect(described_class.get("JCGM 200:2008").docidentifier.first.content).to eq "JCGM 200:2008"
    expect(described_class.get("JCGM 200:2012").docidentifier.first.content).to eq "JCGM 200:2012"
  end

  it "stamps the fetched date" do
    expect(described_class.get("JCGM 17th Meeting (2012)").fetched).to eq Date.today.to_s
  end

  it "fetches the bare GUM / VIM-N guide records" do
    expect(described_class.get("JCGM GUM").docidentifier.first.content).to eq "JCGM GUM"
    expect(described_class.get("JCGM VIM-3").docidentifier.first.content).to eq "JCGM VIM-3"
  end

  it "fetches a corrigendum record" do
    bib = described_class.get "JCGM 200:2008 Corrigendum"
    expect(bib.docidentifier.first.content).to eq "JCGM 200:2008 Corrigendum"
  end

  it "returns nil for an unknown but parseable reference" do
    expect(described_class.get("JCGM 999:2099")).to be_nil
  end

  it "returns nil (not a parser error) for a reference pubid cannot parse" do
    # A malformed reference degrades to a graceful miss, not a Parslet::ParseFailed.
    expect { described_class.get("JCGM not-a-real-id!!") }.not_to raise_error
    expect(described_class.get("JCGM not-a-real-id!!")).to be_nil
  end

  it "accepts a pubid identifier as input" do
    pubid = ::Pubid::Jcgm.parse("JCGM 17th Meeting (2012)")
    expect(described_class.get(pubid).docidentifier.first.content).to eq "JCGM 17th Meeting (2012)"
  end
end
