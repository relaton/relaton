describe Relaton::Doi::Crossref do
  it "get" do
    expect(Relaton::Doi::Crossref).to receive(:get_by_id).with("10.6028/nist.ir.8245").and_return(:message)
    expect(Relaton::Doi::Parser).to receive(:parse).with(:message).and_return(:bibitem)
    expect(described_class.get("doi:10.6028/nist.ir.8245")).to eq :bibitem
  end

  context "get_by_id" do
    let(:agent) { instance_double(Mechanize) }

    before do
      allow(described_class).to receive(:agent).and_return(agent)
    end

    it "success" do
      page = double(body: '{"status": "ok", "message": "message"}')
      expect(agent).to receive(:get).with(
        "https://api.crossref.org/works/10.6028%2Fnist.ir.8245",
      ).and_return(page)
      expect(described_class.get_by_id("10.6028/nist.ir.8245")).to eq "message"
    end

    it "not found" do
      error = Mechanize::ResponseCodeError.new(
        double(code: "404", body: "Not Found"),
      )
      expect(agent).to receive(:get).with(
        "https://api.crossref.org/works/10.6028%2Fnist.ir.8245",
      ).and_raise(error)
      expect(described_class.get_by_id("10.6028/nist.ir.8245")).to be_nil
    end

    it "retry 3 times" do
      error_page = double(
        body: "error",
        response: { "x-rate-limit-interval" => 1 },
      )
      error = Mechanize::ResponseCodeError.new(
        double(code: "500", body: "error", response: error_page.response),
      )
      allow(error).to receive(:page).and_return(error_page)
      expect(agent).to receive(:get).with(
        "https://api.crossref.org/works/10.6028%2Fnist.ir.8245",
      ).exactly(3).times.and_raise(error)
      expect_any_instance_of(Kernel).to receive(:sleep).with(1)
      expect_any_instance_of(Kernel).to receive(:sleep).with(2)
      expect do
        described_class.get_by_id("10.6028/nist.ir.8245")
      end.to raise_error Relaton::RequestError
    end

    it "still backs off when the response carries no rate-limit headers" do
      # The 429s Crossref actually returned had only Date/Content-Length/
      # Connection. Reading a missing header as 0 would retry with no delay at
      # all, hammering the endpoint that just asked us to slow down.
      error_page = double(body: "", response: {})
      error = Mechanize::ResponseCodeError.new(double(code: "429", body: ""))
      allow(error).to receive(:page).and_return(error_page)
      expect(agent).to receive(:get).with(
        "https://api.crossref.org/works/10.6028%2Fnist.ir.8245",
      ).exactly(3).times.and_raise(error)
      expect_any_instance_of(Kernel).to receive(:sleep).with(1)
      expect_any_instance_of(Kernel).to receive(:sleep).with(2)
      expect do
        described_class.get_by_id("10.6028/nist.ir.8245")
      end.to raise_error Relaton::RequestError
    end
  end
end
