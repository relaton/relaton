describe Relaton::Doi::Http do
  let(:agent) { instance_double(Mechanize) }
  let(:url) { "https://api.datacite.org/dois/10.13140%2Frg.2.1.4576.8809" }

  before { allow(described_class).to receive(:agent).and_return(agent) }

  it "answers the parsed JSON body" do
    expect(agent).to receive(:get).with(url).and_return(double(body: '{"data": 1}'))
    expect(described_class.get_json(url, "DataCite")).to eq("data" => 1)
  end

  it "answers nil on a 404" do
    error = Mechanize::ResponseCodeError.new(double(code: "404", body: ""))
    expect(agent).to receive(:get).with(url).and_raise(error)
    expect(described_class.get_json(url, "DataCite")).to be_nil
  end

  it "retries twice with a 1 s floor, then raises Relaton::RequestError" do
    error = Mechanize::ResponseCodeError.new(double(code: "503", body: "busy"))
    allow(error).to receive(:page).and_return(double(body: "busy", response: {}))
    expect(agent).to receive(:get).with(url).exactly(3).times.and_raise(error)
    expect(described_class).to receive(:sleep).with(1).ordered
    expect(described_class).to receive(:sleep).with(2).ordered
    expect { described_class.get_json(url, "DataCite") }
      .to raise_error Relaton::RequestError, /DataCite error/
  end

  it "waits for the Retry-After seconds of a 429" do
    error = Mechanize::ResponseCodeError.new(double(code: "429", body: ""))
    allow(error).to receive(:page)
      .and_return(double(body: "", response: { "retry-after" => "3" }))
    calls = 0
    expect(agent).to receive(:get).with(url).twice do
      calls += 1
      raise error if calls == 1

      double(body: "{}")
    end
    expect(described_class).to receive(:sleep).with(3)
    expect(described_class.get_json(url, "DataCite")).to eq({})
  end

  it "raises Relaton::RequestError on a network error after the retries" do
    expect(agent).to receive(:get).with(url).exactly(3).times
      .and_raise(SocketError, "getaddrinfo")
    allow(described_class).to receive(:sleep)
    expect { described_class.get_json(url, "DataCite") }
      .to raise_error Relaton::RequestError, /getaddrinfo/
  end

  it "treats a non-JSON 200 as a transport failure" do
    expect(agent).to receive(:get).with(url).exactly(3).times
      .and_return(double(body: "<html>Bad gateway</html>"))
    allow(described_class).to receive(:sleep)
    expect { described_class.get_json(url, "DataCite") }
      .to raise_error Relaton::RequestError, /DataCite error/
  end

  it "raises Relaton::RequestError on a TLS failure after the retries" do
    expect(agent).to receive(:get).with(url).exactly(3).times
      .and_raise(OpenSSL::SSL::SSLError, "handshake")
    allow(described_class).to receive(:sleep)
    expect { described_class.get_json(url, "DataCite") }
      .to raise_error Relaton::RequestError, /handshake/
  end
end
