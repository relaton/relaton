RSpec.describe Relaton::Adobe::Ext do
  let(:ext) do
    described_class.new(
      doctype: Relaton::Adobe::Doctype.new(content: "tech-note"),
      flavor: "adobe",
      urn: "urn:adobe:tech-note:5014",
      webpage: "https://github.com/adobe-type-tools/font-tech-notes/blob/main/pdfs/5014.CIDFont_Spec.pdf",
      tech_note_number: "5014",
      source_repo_path: "pdfs/5014.CIDFont_Spec.pdf",
    )
  end

  it "round-trips the Adobe-specific fields through YAML" do
    parsed = described_class.from_yaml(ext.to_yaml)
    expect(parsed.urn).to eq "urn:adobe:tech-note:5014"
    expect(parsed.webpage)
      .to eq "https://github.com/adobe-type-tools/font-tech-notes/blob/main/pdfs/5014.CIDFont_Spec.pdf"
    expect(parsed.tech_note_number).to eq "5014"
    expect(parsed.source_repo_path).to eq "pdfs/5014.CIDFont_Spec.pdf"
    expect(parsed.doctype.content).to eq "tech-note"
  end

  it "round-trips a Publication-style ext with publication_slug" do
    pub = described_class.new(
      doctype: Relaton::Adobe::Doctype.new(content: "publication"),
      flavor: "adobe",
      publication_slug: "adobe-glyph-list",
    )
    parsed = described_class.from_yaml(pub.to_yaml)
    expect(parsed.doctype.content).to eq "publication"
    expect(parsed.publication_slug).to eq "adobe-glyph-list"
  end
end
