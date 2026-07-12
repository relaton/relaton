RSpec.describe Relaton::Adobe::Item do
  let(:hash) do
    {
      "id" => "ATN5014",
      "type" => "standard",
      "title" => [{
        "language" => "eng",
        "content" => "Adobe CMap and CID Font Files Specification",
        "type" => "main",
      }],
      "docidentifier" => [{
        "content" => "Adobe Technical Note #5014",
        "type" => "ADOBE",
        "primary" => true,
      }],
      "ext" => {
        "doctype" => { "content" => "tech-note" },
        "flavor" => "adobe",
        "urn" => "urn:adobe:tech-note:5014",
        "tech_note_number" => "5014",
        "source_repo_path" => "pdfs/5014.CIDFont_Spec.pdf",
      },
    }
  end

  it "round-trips Adobe ext fields through YAML" do
    item = described_class.from_hash(hash)
    yaml = item.to_yaml
    restored = described_class.from_yaml(yaml)

    expect(restored.ext.urn).to eq "urn:adobe:tech-note:5014"
    expect(restored.ext.tech_note_number).to eq "5014"
    expect(restored.ext.source_repo_path).to eq "pdfs/5014.CIDFont_Spec.pdf"
    expect(yaml).to include("urn:adobe:tech-note:5014")
    expect(yaml).to include("tech_note_number: '5014'")
  end

  it "uses Relaton::Adobe::Ext for the ext attribute" do
    item = described_class.from_hash(hash)
    expect(item.ext).to be_a(Relaton::Adobe::Ext)
  end

  it "is aliased as Bibitem and Bibdata" do
    expect(Relaton::Adobe::Bibitem).to be < Relaton::Adobe::Item
    expect(Relaton::Adobe::Bibdata).to be < Relaton::Adobe::Item
  end
end
