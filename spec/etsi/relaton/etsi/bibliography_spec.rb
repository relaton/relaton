describe Relaton::Etsi::Bibliography do
  # Stub the per-document YAML fetch for `file`, asserting the search resolved
  # to exactly that edition's URL.
  def stub_yaml(file)
    url = "#{Relaton::Etsi::Bibliography::SOURCE}#{file}"
    body = File.read("fixtures/item.yaml")
    expect(Net::HTTP).to receive(:get_response)
      .with(URI(url)).and_return(double(code: "200", body: body))
  end

  it "get for a document by docid", vcr: "search_doc" do
    expect do
      item = described_class.get "ETSI GS ZSM 012"
      expect(item).to be_instance_of Relaton::Etsi::ItemData
      expect(item.docidentifier.first.content).to eq "ETSI GS ZSM 012 V1.1.1 (2022-12)"
    end.to output(
      match(/\[relaton-etsi\] INFO: \(ETSI GS ZSM 012\) Fetching from Relaton repository \.\.\./).and(
        match(/\[relaton-etsi\] INFO: \(ETSI GS ZSM 012\) Found: `ETSI GS ZSM 012 V1.1.1 \(2022-12\)`/),
      ),
    ).to_stderr_from_any_process
  end

  it "resolves a bare reference (no version/date) to the latest edition" do
    # The index carries ETSI EN 300 175-1 V1.9.1 (2005-09) and V2.9.1 (2022-03);
    # a version/date-less ref must match both and return the most recent.
    stub_yaml "data/etsi-en-300-175-1-v2-9-1-2022-03.yaml"
    expect { described_class.get "ETSI EN 300 175-1" }.to output.to_stderr_from_any_process
  end

  it "resolves a fully-qualified reference to that exact edition" do
    stub_yaml "data/etsi-en-300-175-1-v1-9-1-2005-09.yaml"
    expect { described_class.get "ETSI EN 300 175-1 V1.9.1 (2005-09)" }.to output.to_stderr_from_any_process
  end

  it "raise network/server error" do
    expect(Net::HTTP).to receive(:get_response).and_raise SocketError
    expect { described_class.get "ETSI GS ZSM 012" }.to raise_error Relaton::RequestError
  end

  it "not found" do
    expect do
      described_class.get "ETSI GS ZSM 011"
    end.to output(/\[relaton-etsi\] INFO: \(ETSI GS ZSM 011\) Not found\./).to_stderr_from_any_process
  end

  it "returns nil (not found) for an unrecognized reference" do
    expect(described_class.search("not an etsi ref")).to be_nil
  end
end
