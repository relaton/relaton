describe Relaton::Doi::Crossref do
  it "get" do
    expect(Relaton::Doi::Crossref).to receive(:get_by_id).with("10.6028/nist.ir.8245").and_return(:message)
    expect(Relaton::Doi::Parser).to receive(:parse).with(:message).and_return(:bibitem)
    expect(described_class.get("doi:10.6028/nist.ir.8245")).to eq :bibitem
  end

  context "get_by_id" do
    let(:agent) do
      { "User-Agent" => "Relaton::Doi (https://www.relaton.org/guides/doi/; mailto:open.source@ribose.com)" }
    end

    it "success" do
      resp = double(status: 200, body: '{"status": "ok", "message": "message"}')
      expect(Faraday).to receive(:get).with(
        "https://api.crossref.org/works/10.6028%2Fnist.ir.8245", nil, agent
      ).and_return(resp)
      expect(described_class.get_by_id("10.6028/nist.ir.8245")).to eq "message"
    end

    it "not found" do
      resp = double(status: 404)
      expect(Faraday).to receive(:get).with(
        "https://api.crossref.org/works/10.6028%2Fnist.ir.8245", nil, agent
      ).and_return(resp)
      expect(described_class.get_by_id("10.6028/nist.ir.8245")).to be_nil
    end

    it "retry 3 times" do
      resp = double(status: 500, body: "error", headers: { "x-rate-limit-interval" => 1 })
      expect(Faraday).to receive(:get).with(
        "https://api.crossref.org/works/10.6028%2Fnist.ir.8245", nil, agent
      ).exactly(3).times.and_return(resp)
      expect_any_instance_of(Kernel).to receive(:sleep).with(1)
      expect_any_instance_of(Kernel).to receive(:sleep).with(2)
      expect { described_class.get_by_id("10.6028/nist.ir.8245") }.to raise_error Relaton::RequestError
    end
  end
end
