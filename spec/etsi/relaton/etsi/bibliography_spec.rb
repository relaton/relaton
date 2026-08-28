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

  it "orders a multi-digit version numerically, not as a string" do
    # ETSI TR 155 919 runs V3.0.0 .. V19.0.0 in the index. String order puts
    # V9.0.0 (2010-02) on top, so a bare ref must not resolve to that edition.
    stub_yaml "data/etsi-tr-155-919-v19-0-0-2025-10.yaml"
    expect { described_class.get "ETSI TR 155 919" }.to output.to_stderr_from_any_process
  end

  it "orders the `ed.N` form numerically too" do
    # ETSI ETS 300 974 has ed.9 (1999-12) and ed.11 (2000-12); string order
    # puts ed.9 on top.
    stub_yaml "data/etsi-ets-300-974-ed-11-2000-12.yaml"
    expect { described_class.get "ETSI ETS 300 974" }.to output.to_stderr_from_any_process
  end

  it "breaks a version tie on the publication date" do
    # Two editions share V1.1.1, so the version arrays compare equal and the
    # date decides. Built in memory: the fixture index has no such pair.
    index = Relaton::Index::Type.new :etsi
    index.instance_variable_set :@index, [
      { id: ::Pubid::Etsi.parse("ETSI GS ZSM 099 V1.1.1 (2020-01)"), file: "data/old.yaml" },
      { id: ::Pubid::Etsi.parse("ETSI GS ZSM 099 V1.1.1 (2024-06)"), file: "data/new.yaml" },
    ]
    row = described_class.best_match index, ::Pubid::Etsi.parse("ETSI GS ZSM 099")
    expect(row[:file]).to eq "data/new.yaml"
  end

  it "resolves a part-less reference to one of its parts" do
    # ETSI EN 300 175 has parts 1..8 in the index; a part-less ref matches them
    # all (part excluded) and resolves to one of them rather than nothing.
    captured = nil
    allow(Net::HTTP).to receive(:get_response) do |uri|
      captured = uri.to_s
      double(code: "200", body: File.read("fixtures/item.yaml"))
    end
    described_class.get "ETSI EN 300 175"
    expect(captured).to match(%r{/data/etsi-en-300-175-\d+-})
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

  it "raises Parslet::ParseFailed for an unrecognized reference" do
    # Mirrors ISO: the parse error propagates so the CLI can render a friendly
    # "not a recognized standards identifier" message.
    expect { described_class.search("@@ not a ref @@") }.to raise_error Parslet::ParseFailed
  end
end
