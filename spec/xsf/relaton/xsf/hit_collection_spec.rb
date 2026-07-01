describe Relaton::Xsf::HitCollection do
  subject(:collection) { Relaton::Xsf::HitCollection.new "XEP 0001" }

  it "raise Relaton::RequestError" do
    expect(subject).to receive(:index).and_raise Timeout::Error, "timeout"
    expect { subject.search }.to raise_error Relaton::RequestError, "timeout"
  end
end
