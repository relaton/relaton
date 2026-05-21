RSpec.describe Relaton::Core::HitCollection do
  subject do
    hits = described_class.new("ref")
    hit = Relaton::Core::Hit.new({}, hits)
    item = double "bibitem"
    expect(item).to receive(:to_xml).at_most :once
    expect(hit).to receive(:item).and_return(item).at_most :twice
    hits << hit
    hits
  end

  xit "#index" do
    expect(subject.index).to be_instance_of Relaton::Index
  end

  it("fetches all hits") { subject.fetch }

  it "select hits" do
    expect(subject.select!).to be_instance_of described_class
  end

  it "select returns a new collection with independent hit copies" do
    original = subject
    selected = original.select { true }

    expect(selected).to be_instance_of described_class
    expect(selected).not_to equal original
    expect(selected.size).to eq original.size

    selected.each do |hit|
      expect(hit.hit_collection.__getobj__).to equal selected
    end

    original.each do |hit|
      expect(hit.hit_collection.__getobj__).to equal original
    end
  end

  it "collection to xml" do
    expect(subject.to_xml).to eq %{<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<documents/>\n}
  end

  it "reduce collection" do
    subject.reduce!([]) { |sum, hit| sum << hit }
    expect(subject).to be_instance_of described_class
  end

  it "returns string" do
    expect(subject.to_s).to eq(
      "<Relaton::Core::HitCollection:#{format('%#.14x', subject.object_id << 1)} "\
      "@ref=ref @fetched=false>",
    )
  end
end
