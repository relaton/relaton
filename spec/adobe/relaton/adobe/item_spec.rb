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
        "content" => "Adobe TN 5014",
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

  it "preserves the Adobe TN citation form in docidentifier.content" do
    item = described_class.from_hash(hash)
    expect(item.docidentifier.first.content).to eq "Adobe TN 5014"
  end

  it "uses Relaton::Adobe::Ext for the ext attribute" do
    item = described_class.from_hash(hash)
    expect(item.ext).to be_a(Relaton::Adobe::Ext)
  end

  it "is aliased as Bibitem and Bibdata" do
    expect(Relaton::Adobe::Bibitem).to be < Relaton::Adobe::Item
    expect(Relaton::Adobe::Bibdata).to be < Relaton::Adobe::Item
  end

  context "with a named-publication item (Adobe Publication <title>)" do
    let(:pub_hash) do
      {
        "id" => "adobe-glyph-list",
        "type" => "standard",
        "title" => [{
          "language" => "eng",
          "content" => "Adobe Glyph List",
          "type" => "main",
        }],
        "docidentifier" => [{
          "content" => "Adobe Publication Adobe Glyph List",
          "type" => "ADOBE",
          "primary" => true,
        }],
        "ext" => {
          "doctype" => { "content" => "publication" },
          "flavor" => "adobe",
          "urn" => "urn:adobe:publication:adobe-glyph-list",
          "publication_slug" => "adobe-glyph-list",
        },
      }
    end

    it "round-trips the publication citation form" do
      item = described_class.from_hash(pub_hash)
      yaml = item.to_yaml
      restored = described_class.from_yaml(yaml)
      expect(restored.docidentifier.first.content)
        .to eq "Adobe Publication Adobe Glyph List"
      expect(restored.ext.publication_slug).to eq "adobe-glyph-list"
    end
  end
end
