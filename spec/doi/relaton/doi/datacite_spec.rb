describe Relaton::Doi::Datacite do
  let(:url) { "https://api.datacite.org/dois/10.13140%2FRG.2.1.4576.8809" }

  it "parses the attributes of the record DataCite answers" do
    attrs = { "doi" => "10.13140/rg.2.1.4576.8809" }
    expect(Relaton::Doi::Http).to receive(:get_json).with(url, "DataCite")
      .and_return("data" => { "attributes" => attrs })
    expect(Relaton::Doi::DataciteParser).to receive(:parse).with(attrs)
      .and_return(:bibitem)
    expect do
      expect(described_class.get("doi:10.13140/RG.2.1.4576.8809")).to eq :bibitem
    end.to output(
      include("(doi:10.13140/RG.2.1.4576.8809) Fetching from api.datacite.org ...",
              "Found: `10.13140/rg.2.1.4576.8809`"),
    ).to_stderr_from_any_process
  end

  it "answers nil when DataCite has no record" do
    expect(Relaton::Doi::Http).to receive(:get_json).with(url, "DataCite").and_return(nil)
    expect do
      expect(described_class.get("10.13140/RG.2.1.4576.8809")).to be_nil
    end.to output(/Not found\./).to_stderr_from_any_process
  end
end
