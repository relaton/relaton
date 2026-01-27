RSpec.describe Relaton::Iana::Bibliography do
  it "raise RequestError" do
    expect(Relaton::Index).to receive(:find_or_create).and_raise(SocketError)
    expect do
      described_class.get "ref"
    end.to raise_error Relaton::RequestError
  end
end
