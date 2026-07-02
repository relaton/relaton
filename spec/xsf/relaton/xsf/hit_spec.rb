describe Relaton::Xsf::Hit do
  subject { Relaton::Xsf::Hit.new url: "https://example.com" }

  it "raises Relaton::RequestError" do
    agent = double "agent"
    expect(agent).to receive(:get).and_raise SocketError
    expect(Mechanize).to receive(:new).and_return agent
    expect { subject.item }.to raise_error Relaton::RequestError
  end
end
