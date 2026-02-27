require "relaton/ogc/data_fetcher"

describe Relaton::Ogc::Bibliography do
  it "raise request error" do
    expect(Relaton::Ogc::HitCollection).to receive(:new)
      .and_raise Faraday::ConnectionFailed.new(nil)
    expect do
      described_class.search("ref")
    end.to raise_error Relaton::RequestError
  end
end
