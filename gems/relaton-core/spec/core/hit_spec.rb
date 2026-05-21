RSpec.describe Relaton::Core::Hit do
  subject { described_class.new({}) }

  it "returns string" do
    expect(subject.to_s).to eq(
      "<Relaton::Core::Hit:#{format('%#.14x', subject.object_id << 1)} " \
      '@reference="" @fetched="false" @docidentifier="">',
    )
  end

  context "fetched?" do
    it "false" do
      expect(subject.fetched?).to be false
    end

    it "true" do
      subject.instance_variable_set :@item, Object.new
      expect(subject.fetched?).to be true
    end
  end

  xit "to xml" do
    item = double "bibitem"
    expect(subject).to receive(:fetch).and_return item
    expect(item).to receive(:to_xml).and_return "<bibitem/>"
    expect(subject.to_xml).to match(/<bibitem schema-version="v\d+\.\d+\.\d+"\/>/)
  end

  it "raise not implemented" do
    expect { subject.item }.to raise_error "Not implemented"
  end
end
