RSpec.describe Relaton::Ieee::Docidentifier do
  describe "#remove_date!" do
    it "strips the year" do
      docid = described_class.new(type: "IEEE", content: "IEEE Std 528-2019", primary: true)
      docid.remove_date!
      expect(docid.content).to eq "IEEE Std 528"
    end

    it "keeps the trademark" do
      docid = described_class.new(type: "IEEE", content: "IEEE Std 528™-2019", scope: "trademark")
      docid.remove_date!
      expect(docid.content).to eq "IEEE Std 528™"
    end

    it "leaves an id with no year as it is" do
      docid = described_class.new(type: "IEEE", content: "IEEE P802.5t™/D-2.5", scope: "trademark")
      docid.remove_date!
      expect(docid.content).to eq "IEEE P802.5t™/D-2.5"
    end

    it "leaves an ISBN as it is" do
      docid = described_class.new(type: "ISBN", content: "978-1-5044-5983-9")
      docid.remove_date!
      expect(docid.content).to eq "978-1-5044-5983-9"
    end
  end
end
