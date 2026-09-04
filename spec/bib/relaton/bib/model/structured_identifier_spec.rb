describe Relaton::Bib::StructuredIdentifier do
  # Same reasoning as Bib::Docidentifier: `#ext_to_all_parts!` and
  # `#ext_remove_date` broadcast to every structured identifier, so the default
  # is a no-op and flavors that model a part or a date override it (see
  # Relaton::Iso::StructuredIdentifier).
  subject(:si) { described_class.new(docnumber: "123", partnumber: "1", year: "2020") }

  it "no-ops instead of raising" do
    expect { si.remove_part! }.not_to raise_error
    expect { si.to_all_parts! }.not_to raise_error
    expect { si.remove_date! }.not_to raise_error
  end

  it "leaves the attributes unchanged" do
    si.remove_part!
    si.to_all_parts!
    si.remove_date!
    expect([si.docnumber, si.partnumber, si.year]).to eq %w[123 1 2020]
  end
end
