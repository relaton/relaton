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

  context "with the published records (relaton-data-adobe, 2026-11-24)" do
    def record(name)
      described_class.from_yaml File.read("fixtures/#{name}.yaml", encoding: "UTF-8")
    end

    def publisher(item)
      item.contributor.find { |c| c.role.any? { |r| r.type == "publisher" } }.organization
    end

    it "reads a versioned publication from adobe/dc-acrobat-sdk-docs" do
      item = record("pdf-reference-1.7")
      expect(item.ext.doctype.content).to eq "publication"
      # The primary docid is the canonical id (relaton-data-adobe#12), so it
      # parses to the same pubid as the citation: the Db cache and the
      # api.relaton.org key check both rest on that.
      docid = item.docidentifier.first
      expect(docid.content).to eq "Adobe Publication pdf-reference-1.7"
      expect(docid.pubid).to eq ::Pubid::Adobe.parse("Adobe Publication pdf-reference-1.7")
      expect(item.ext.urn).to eq "urn:adobe:publication:pdf-reference:v1.7"
      expect(item.ext.publication_slug).to eq "pdf-reference"
      expect(item.ext.source_repo_path).to eq "docs/pdfstandards/pdfreference1.7old.pdf"
      expect(publisher(item).name.first.content).to eq "Adobe Systems Incorporated"
      expect(publisher(item).abbreviation.content).to eq "Adobe"
    end

    it "reads a tech note mirrored at pdfa.org/norm-refs" do
      item = record("atn5620")
      expect(item.docidentifier.first.content).to eq "Adobe TN 5620"
      expect(item.docidentifier.first.pubid.to_s).to eq "Adobe TN 5620"
      expect(item.ext.tech_note_number).to eq "5620"
      expect(item.ext.webpage).to eq "https://www.pdfa.org/norm-refs/5620.PortableJobTicket.pdf"
      expect(publisher(item).name.first.content).to eq "Adobe Systems Incorporated"
    end

    it "re-serializes both records to the same YAML" do
      %w[pdf-reference-1.7 atn5620].each do |name|
        item = record(name)
        expect(described_class.from_yaml(item.to_yaml).to_yaml).to eq item.to_yaml
      end
    end
  end
end
