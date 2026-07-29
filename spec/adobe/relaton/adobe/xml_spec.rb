require "tempfile"

# Validates that the XML produced by an Adobe Item conforms to the RelaxNG
# grammar in grammar/relaton-adobe(-compile).rng. Guards the ext-element
# mapping (a wrong element name would round-trip through YAML but fail here).
RSpec.describe "Relaton::Adobe XML schema" do
  # CWD is spec/adobe/, so ../../grammar resolves to the repo-root grammar/ dir
  # (same convention as spec/bib/relaton/bib/model/bibdata_spec.rb).
  let(:schema) { Jing.new "../../grammar/relaton-adobe-compile.rng" }

  def validate(item)
    Tempfile.create(["adobe", ".xml"]) do |f|
      f.write item.to_xml(bibdata: true)
      f.flush
      schema.validate f.path
    end
  end

  it "validates a tech-note item against the grammar" do
    item = Relaton::Adobe::Item.from_hash(
      "id" => "ATN5014",
      "type" => "standard",
      "title" => [{ "language" => "eng", "content" => "Adobe CMap and CID Font Files Specification", "type" => "main" }],
      "docidentifier" => [{ "content" => "Adobe TN 5014", "type" => "ADOBE", "primary" => true }],
      "ext" => {
        "doctype" => { "content" => "tech-note" },
        "flavor" => "adobe",
        "urn" => "urn:adobe:tech-note:5014",
        "webpage" => "https://github.com/adobe-type-tools/font-tech-notes/blob/main/pdfs/5014.CIDFont_Spec.pdf",
        "tech_note_number" => "5014",
        "source_repo_path" => "pdfs/5014.CIDFont_Spec.pdf",
      },
    )
    expect(validate(item)).to eq []
  end

  it "validates a named-publication item against the grammar" do
    item = Relaton::Adobe::Item.from_hash(
      "id" => "adobe-glyph-list",
      "type" => "standard",
      "title" => [{ "language" => "eng", "content" => "Adobe Glyph List", "type" => "main" }],
      "docidentifier" => [{ "content" => "Adobe Publication Adobe Glyph List", "type" => "ADOBE", "primary" => true }],
      "ext" => {
        "doctype" => { "content" => "publication" },
        "flavor" => "adobe",
        "urn" => "urn:adobe:publication:adobe-glyph-list",
        "publication_slug" => "adobe-glyph-list",
      },
    )
    expect(validate(item)).to eq []
  end
end
