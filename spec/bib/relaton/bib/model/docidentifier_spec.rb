describe Relaton::Bib::Docidentifier do
  # `Bib::ItemData#to_all_parts` / `#to_most_recent_reference` broadcast these
  # to every docidentifier unconditionally. They used to raise
  # NotImplementedError here, which made both calls unusable for the 13 flavors
  # that never subclassed this class. The default is now a no-op; a flavor
  # whose identifier carries a part or a date overrides it (see
  # Relaton::Ogc::Docidentifier).
  subject(:docid) { described_class.new(content: "ABC 123", type: "ABC") }

  it "no-ops instead of raising" do
    expect { docid.remove_part! }.not_to raise_error
    expect { docid.to_all_parts! }.not_to raise_error
    expect { docid.remove_date! }.not_to raise_error
  end

  it "leaves the content unchanged" do
    docid.remove_part!
    docid.to_all_parts!
    docid.remove_date!
    expect(docid.content).to eq "ABC 123"
  end
end
