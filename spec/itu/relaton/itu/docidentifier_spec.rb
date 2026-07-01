describe Relaton::Itu::Docidentifier do
  it "inherits from Bib::Docidentifier" do
    expect(described_class).to be < Relaton::Bib::Docidentifier
  end

  describe "#remove_date!" do
    it "removes month/year date" do
      docid = described_class.new(type: "ITU", content: "ITU-T L.163 (11/2018)", primary: true)
      docid.remove_date!
      expect(docid.content).to eq "ITU-T L.163"
    end

    it "removes year-only date" do
      docid = described_class.new(type: "ITU", content: "ITU-R RR (2020)", primary: true)
      docid.remove_date!
      expect(docid.content).to eq "ITU-R RR"
    end

    it "removes multiple dates" do
      docid = described_class.new(type: "ITU", content: "H.264 (2005) Amd. 1 (06/2006)", primary: true)
      docid.remove_date!
      expect(docid.content).to eq "H.264 Amd. 1"
    end

    it "leaves identifier unchanged when no date present" do
      docid = described_class.new(type: "ITU", content: "ITU-T G.989.2 Amd 1", primary: true)
      docid.remove_date!
      expect(docid.content).to eq "ITU-T G.989.2 Amd 1"
    end

    it "does not remove version markers" do
      docid = described_class.new(type: "ITU", content: "ITU-T H.264 (V14) (08/2021)", primary: true)
      docid.remove_date!
      expect(docid.content).to eq "ITU-T H.264 (V14)"
    end
  end
end
