RSpec.describe Relaton::Nist::Bibliography do
  it "raise error when search" do
    expect(Relaton::Nist::HitCollection).to receive(:new).and_raise SocketError
    expect do
      Relaton::Nist::Bibliography.search("NISTIR 7831")
    end.to raise_error Relaton::RequestError
  end

  describe ".parse_iteration" do
    subject { described_class.send(:parse_iteration, stage) }

    context "with 'IPD'" do
      let(:stage) { "IPD" }

      it { is_expected.to eq "1" }
    end

    context "with 'FPD'" do
      let(:stage) { "FPD" }

      it { is_expected.to eq "final" }
    end

    context "with '2PD'" do
      let(:stage) { "2PD" }

      it { is_expected.to eq "2" }
    end

    context "with 'PD-F'" do
      let(:stage) { "PD-F" }

      it { is_expected.to eq "final" }
    end

    context "with nil" do
      let(:stage) { nil }

      it { is_expected.to be_nil }
    end
  end

  describe ".match_date?" do
    let(:bib_date_class) { Relaton::Bib::Date }

    def make_item(dates)
      item = double("item")
      allow(item).to receive(:date).and_return(dates)
      item
    end

    it "returns true when a date's at matches" do
      d = bib_date_class.new(type: "published", at: "2020-06-15")
      item = make_item([d])
      result = described_class.send(:match_date?, item, Date.new(2020, 6, 15))
      expect(result).to be true
    end

    it "returns true when a date's from matches" do
      d = bib_date_class.new(type: "published", from: "2021-03-01")
      item = make_item([d])
      result = described_class.send(:match_date?, item, Date.new(2021, 3, 1))
      expect(result).to be true
    end

    it "returns false when no dates match" do
      d = bib_date_class.new(type: "published", at: "2020-01-01")
      item = make_item([d])
      result = described_class.send(:match_date?, item, Date.new(2022, 12, 31))
      expect(result).to be false
    end
  end

  describe ".match_year?" do
    let(:bib_date_class) { Relaton::Bib::Date }

    def make_item(dates)
      item = double("item")
      allow(item).to receive(:date).and_return(dates)
      item
    end

    it "returns the year when it matches" do
      d = bib_date_class.new(type: "published", at: "2020-06-15")
      item = make_item([d])
      result = described_class.send(:match_year?, item, "2020")
      expect(result).to eq 2020
    end

    it "yields missed years when they don't match" do
      d = bib_date_class.new(type: "published", at: "2019-03-01")
      item = make_item([d])
      missed = []
      result = described_class.send(:match_year?, item, "2020") { |y| missed << y }
      expect(result).to be_nil
      expect(missed).to eq [2019]
    end

    it "returns nil when no date values exist" do
      d = bib_date_class.new(type: "published")
      item = make_item([d])
      result = described_class.send(:match_year?, item, "2020")
      expect(result).to be_nil
    end

    it "ignores non-published/issued date types" do
      d = bib_date_class.new(type: "created", at: "2020-06-15")
      item = make_item([d])
      result = described_class.send(:match_year?, item, "2020")
      expect(result).to be_nil
    end
  end

  # CSRC lists neither the legacy dated CSWP ids nor the translations; both
  # come from the NIST Library RIS files through Cswp (relaton#406).
  describe "CSWP ids that CSRC does not list" do
    def docids(item)
      item.docidentifier.map { |d| [d.content, d.primary] }
    end

    it "answers a legacy dated id with the numbered CSRC record" do
      item = described_class.get "NIST CSWP 01142020"
      expect(docids(item)).to include(["NIST CSWP 9", true], ["NIST CSWP 01142020", nil])
      expect(item.source.map { |s| s.content.to_s }).to include(
        "https://csrc.nist.gov/pubs/cswp/9/a-taxonomic-approach-to-understanding-emerging-blo/final",
      )
    end

    it "answers a dated case study with its lettered number" do
      item = described_class.get "NIST CSWP 02042020-2"
      expect(docids(item)).to include(["NIST CSWP 11A", true], ["NIST CSWP 02042020-2", nil])
    end

    it "answers the dated draft with the CSRC draft" do
      item = described_class.get "NIST CSWP 06222021-draft"
      expect(item.docidentifier.first.content).to eq "NIST CSWP 19 ipd"
      expect(docids(item)).to include(["NIST CSWP 06222021-draft", nil])
    end

    it "accepts the DOI form of a dated id" do
      item = described_class.get "NIST.CSWP.04162018"
      expect(item.docidentifier.first.content).to eq "NIST CSWP 6"
    end

    ["NIST.CSWP.6.spa", "NIST CSWP 6(spa)", "NIST CSWP 04162018es"].each do |ref|
      it "answers #{ref} with the Spanish translation record" do
        item = described_class.get ref
        expect(item.docidentifier.first.content).to eq "NIST CSWP 6(spa)"
        expect(item.language).to eq ["es"]
        expect(item.relation.first.type).to eq "translatedFrom"
      end
    end

    it "answers a translation for its own year only" do
      expect(described_class.get("NIST CSWP 6 spa", "2018").language).to eq ["es"]
      expect(described_class.get("NIST CSWP 6 spa", "2020")).to be_nil
    end

    it "answers not-found for an EO Response id" do
      expect(described_class.get("NIST CSWP 02042022-1")).to be_nil
    end
  end
end
