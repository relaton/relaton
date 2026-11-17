describe Relaton::Doi::RegistrationAgency do
  def answer(hash)
    expect(Relaton::Doi::Http).to receive(:get_json)
      .with("https://doi.org/ra/10.13140%2FRG.2.1.4576.8809", "doi.org")
      .and_return([{ "DOI" => "10.13140/RG.2.1.4576.8809" }.merge(hash)])
  end

  it "answers the agency doi.org names" do
    answer "RA" => "DataCite"
    expect(described_class.lookup("10.13140/RG.2.1.4576.8809")).to eq "DataCite"
  end

  it "answers Crossref" do
    answer "RA" => "Crossref"
    expect(described_class.lookup("10.13140/RG.2.1.4576.8809")).to eq "Crossref"
  end

  ["DOI does not exist", "Invalid DOI"].each do |status|
    it "answers nil for the status #{status.inspect}" do
      answer "status" => status
      expect(described_class.lookup("10.13140/RG.2.1.4576.8809")).to be_nil
    end
  end

  it "answers nil when doi.org answers 404" do
    expect(Relaton::Doi::Http).to receive(:get_json).and_return(nil)
    expect(described_class.lookup("10.13140/RG.2.1.4576.8809")).to be_nil
  end

  it "lets a transport failure raise" do
    expect(Relaton::Doi::Http).to receive(:get_json)
      .and_raise(Relaton::RequestError, "doi.org error")
    expect { described_class.lookup("10.13140/RG.2.1.4576.8809") }
      .to raise_error Relaton::RequestError
  end
end
