RSpec.describe Relaton::Gost::Bibliography do
  # The offline pubid-structured index (spec/gost/fixtures/index-v2.zip) and the
  # per-document YAMLs (spec/gost/fixtures/data/*.yaml) are real records copied
  # from relaton-data-gost; they are pre-loaded / served by spec/gost/support/webmock.rb.
  # Fixture contents:
  #   interstate GOST 1.0 — editions 2015 and 92 (for undated -> latest)
  #   national   GOST R 34.12-2015

  context "dated national reference" do
    subject { described_class.get "GOST R 34.12-2015" }

    it "returns the matching record" do
      expect(subject).to be_instance_of Relaton::Gost::ItemData
      expect(subject.docidentifier.first.content).to eq "GOST R 34.12-2015"
    end

    it "stamps the fetched date" do
      expect(subject.fetched).to eq Date.today.to_s
    end
  end

  context "Cyrillic reference" do
    it "normalises through Pubid::Gost and resolves the same record" do
      result = described_class.get "ГОСТ Р 34.12-2015"
      expect(result.docidentifier.first.content).to eq "GOST R 34.12-2015"
    end
  end

  context "undated interstate reference" do
    it "returns the latest edition (2015, not 92)" do
      result = described_class.get "GOST 1.0"
      expect(result).to be_instance_of Relaton::Gost::ItemData
      # undated citation renders undated via to_most_recent_reference
      expect(result.docidentifier.first.content).to eq "GOST 1.0"
      # ...but it is the latest edition's record (2015 urn), not the 1992 one
      expect(result.ext.urn).to eq "urn:gost:std:1.0:2015"
    end

    it "pins the edition when a dated citation is given" do
      result = described_class.get "GOST 1.0-92"
      expect(result.docidentifier.first.content).to eq "GOST 1.0-92"
      expect(result.ext.urn).to eq "urn:gost:std:1.0:92"
    end

    it "pins the edition when the year is passed as an argument" do
      result = described_class.get "GOST 1.0", "92"
      expect(result.docidentifier.first.content).to eq "GOST 1.0-92"
    end
  end

  context "not found" do
    it "returns nil for an unknown code" do
      expect(described_class.get("GOST R 99999-99")).to be_nil
    end
  end

  context "network failure" do
    it "raises Relaton::RequestError on a non-200 from the data repo" do
      allow(Net::HTTP).to receive(:get_response)
        .and_return(instance_double(Net::HTTPNotFound, code: "404"))
      expect { described_class.get "GOST R 34.12-2015" }
        .to raise_error Relaton::RequestError
    end
  end
end
