# frozen_string_literal: true

require "relaton/iso/processor"
require "relaton/db"

# relaton-iso#139: ISO/TC committee documents ("ISO/TC 184/SC 4 N3500:2020").
# relaton-data-iso keeps them in its curated `static/` set; their index rows
# carry no year, so the year of a dated reference is the document's own
# publication date.
RSpec.describe Relaton::Iso::Bibliography do
  let(:row) do
    {
      id: {
        _type: "pubid:iso:tc-document", number: "3500", tc_type: "TC",
        tc_number: "184", sc_type: "SC", sc_number: "4"
      },
      file: "static/iso-tc-184-sc-4-n3500.yaml",
    }
  end
  let(:item) do
    Relaton::Iso::Item.from_yaml(
      File.read("fixtures/iso-tc-184-sc-4-n3500.yaml", encoding: "UTF-8"),
    )
  end

  before do
    allow(described_class).to receive(:search) do |pubid, opts|
      hc = Relaton::Iso::HitCollection.new(pubid, opts)
      hit = Relaton::Iso::Hit.new(row, hc)
      hit.item = item
      hc.instance_variable_set(:@array, [hit])
      hc
    end
  end

  def docid(bib)
    bib.docidentifier.find(&:primary).content
  end

  it "finds an undated reference" do
    bib = described_class.get("ISO/TC 184/SC 4 N3500")
    expect(docid(bib)).to eq "ISO/TC 184/SC 4 N3500"
  end

  it "finds a reference dated with the document's publication year" do
    bib = described_class.get("ISO/TC 184/SC 4 N3500:2020")
    expect(docid(bib)).to eq "ISO/TC 184/SC 4 N3500"
  end

  it "finds a reference with the year as an argument" do
    bib = described_class.get("ISO/TC 184/SC 4 N3500", "2020")
    expect(docid(bib)).to eq "ISO/TC 184/SC 4 N3500"
  end

  it "does not find a reference dated with another year" do
    expect do
      expect(described_class.get("ISO/TC 184/SC 4 N3500:2019")).to be_nil
    end.to output(
      /No match for edition year 2019, but matches exist for `ISO\/TC 184\/SC 4 N3500:2020`/,
    ).to_stderr_from_any_process
  end

  it "finds a reference inside a publication date cutoff" do
    bib = described_class.get(
      "ISO/TC 184/SC 4 N3500:2020", nil, publication_date_before: Date.new(2025, 1, 1)
    )
    expect(docid(bib)).to eq "ISO/TC 184/SC 4 N3500"
  end

  it "does not find a reference outside a publication date cutoff" do
    bib = described_class.get(
      "ISO/TC 184/SC 4 N3500", nil, publication_date_before: Date.new(2019, 1, 1)
    )
    expect(bib).to be_nil
  end

  it "does not answer a dated reference when the document has no year" do
    item.date = []
    expect(described_class.get("ISO/TC 184/SC 4 N3500:2020")).to be_nil
  end

  describe "Relaton::Db cache" do
    let(:processor) { Relaton::Iso::Processor.new }

    it "keys a dated document with its published year" do
      pubid = Pubid::Iso::Identifier.parse("ISO/TC 184/SC 4 N3500")
      expect(processor.item_cache_key(pubid, item).to_s)
        .to eq "ISO/TC 184/SC 4 N 3500:2020"
      expect(pubid.date).to be_nil # not mutated
    end

    it "keeps the key of the undated form" do
      pubid = Pubid::Iso::Identifier.parse("ISO/TC 184/SC 4 N3500")
      undated = item.to_most_recent_reference
      expect(processor.item_cache_key(pubid, undated)).to be pubid
    end

    it "does not overwrite the undated reference with a dated fetch" do
      Dir.mktmpdir do |dir|
        db = Relaton::Db.new(dir, nil)
        undated = db.fetch("ISO/TC 184/SC 4 N3500")
        expect(undated.date).to be_empty
        db.fetch("ISO/TC 184/SC 4 N3500:2020")
        expect(db.fetch("ISO/TC 184/SC 4 N3500").date).to be_empty
      end
    end
  end

  context "when the document is not in the data" do
    before do
      allow(described_class).to receive(:search) do |pubid, opts|
        Relaton::Iso::HitCollection.new(pubid, opts)
      end
    end

    it "does not suggest an all-parts reference" do
      expect do
        expect(described_class.get("ISO/TC 184/SC 4 N3422:2020")).to be_nil
      end.not_to output(/all parts/).to_stderr_from_any_process
    end

    it "explains that committee documents come from a curated set" do
      expect { described_class.get("ISO/TC 184/SC 4 N3422:2020") }
        .to output(/ISO\/TC committee documents are not public/).to_stderr_from_any_process
    end
  end
end
