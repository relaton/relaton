RSpec.describe Relaton::Plateau::Hit do
  let(:hit_hash) { { id: "PLATEAU Handbook #00 1.0", file: "data/plateau-handbook-00-10.yaml" } }
  let(:collection) { double(Relaton::Plateau::HitCollection) }
  subject { described_class.new(hit_hash, collection) }

  it "inherits from Core::Hit" do
    expect(described_class).to be < Relaton::Core::Hit
  end

  it "stores hit hash" do
    expect(subject.hit).to eq hit_hash
  end

  it "fetches item" do
    yaml = File.read "fixtures/item.yaml", encoding: "UTF-8"
    response = double(Net::HTTPResponse, body: yaml)
    expect(Net::HTTP).to receive(:get_response).with(
      URI("#{Relaton::Plateau::HitCollection::ENDPOINT}data/plateau-handbook-00-10.yaml")
    ).and_return(response)
    item = subject.item
    expect(item.docidentifier.first.content).to eq "PLATEAU Handbook #00 1.0"
  end

  it "caches item" do
    yaml = File.read "fixtures/item.yaml", encoding: "UTF-8"
    response = double(Net::HTTPResponse, body: yaml)
    expect(Net::HTTP).to receive(:get_response).once.and_return(response)
    subject.item
    subject.item
  end
end
