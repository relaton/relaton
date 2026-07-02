RSpec.describe Relaton::Ieee::Bibliography do
  it "raise RequestError is domain not reacheable" do
    expect(Relaton::Index).to receive(:find_or_create).and_raise Faraday::ConnectionFailed.new("Connection error")
    expect { described_class.search "ref" }.to raise_error Relaton::RequestError
  end
end
