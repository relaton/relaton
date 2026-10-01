RSpec.describe Relaton::Ieee::Bibliography do
  it "raise RequestError is domain not reacheable" do
    expect(Relaton::Index).to receive(:find_or_create).and_raise Faraday::ConnectionFailed.new("Connection error")
    expect { described_class.search "ref" }.to raise_error Relaton::RequestError
  end

  # relaton#205: Relaton::Db passes the pubid it parsed. It is used as it is,
  # not parsed a second time.
  it "takes a parsed pubid without a second parse" do
    pubid = Pubid::Ieee::Identifier.parse "IEEE 528-2019"
    expect(described_class.send(:parse_pubid, pubid)).to be pubid
  end
end
