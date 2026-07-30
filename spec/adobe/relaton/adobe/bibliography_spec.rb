# frozen_string_literal: true

RSpec.describe Relaton::Adobe::Bibliography do
  # Build an index row the way Relaton::Index would after deserializing with
  # pubid_class: :id is a real Pubid::Adobe identifier.
  def row(ref, file)
    { id: ::Pubid::Adobe.parse(ref), file: file }
  end

  def yaml_for(docid, ext = {})
    {
      "id" => "rec",
      "type" => "standard",
      "docidentifier" => [{ "content" => docid, "type" => "ADOBE", "primary" => true }],
      "title" => [{ "content" => "T", "language" => "eng", "type" => "main" }],
      "ext" => { "doctype" => { "content" => "tech-note" }, "flavor" => "adobe" }.merge(ext),
    }.to_yaml
  end

  # Stub the private index with a double whose #search applies the block over
  # the given rows (matching Relaton::Index::Type#search semantics) and records
  # the id argument, so tests can assert the narrowing branch
  # (tech note -> pubid, publication -> nil).
  attr_reader :search_args

  def stub_index(rows)
    idx = instance_double(Relaton::Index::Type)
    @search_args = []
    allow(idx).to receive(:search) do |arg, &blk|
      @search_args << arg
      blk ? rows.select { |r| blk.call(r) } : rows
    end
    allow(described_class).to receive(:index).and_return(idx)
  end

  context "tech notes" do
    before do
      stub_index([row("Adobe Technical Note #5014", "data/5014.yaml"),
                  row("Adobe Technical Note #5902", "data/5902.yaml")])
      stub_request(:get, "#{described_class::ENDPOINT}data/5014.yaml")
        .to_return(status: 200, body: yaml_for("Adobe TN 5014", "tech_note_number" => "5014"))
    end

    it "resolves the formal citation form and narrows the index by number" do
      item = described_class.get("Adobe Technical Note #5014")
      expect(item).to be_a(Relaton::Adobe::ItemData)
      expect(item.docidentifier.first.content).to eq "Adobe TN 5014"
      expect(item.fetched).to eq Date.today.to_s
      # a numbered tech note is passed to the index for binary-search narrowing
      expect(search_args.last).to be_a(::Pubid::Adobe::Identifiers::TechNote)
      expect(search_args.last.number).to eq "5014"
    end

    it "resolves the ATN alias to the same record" do
      item = described_class.get("ATN5014")
      expect(item.docidentifier.first.content).to eq "Adobe TN 5014"
    end

    it "returns nil when the number is not in the index" do
      expect { expect(described_class.get("ATN9999")).to be_nil }
        .to output(/\[relaton-adobe\] INFO: \(Adobe TN 9999\) Not found\./)
        .to_stderr_from_any_process
    end
  end

  context "named publications (no number — index is scanned)" do
    before do
      stub_index([row("Adobe Publication adobe-glyph-list", "data/agl.yaml")])
      stub_request(:get, "#{described_class::ENDPOINT}data/agl.yaml")
        .to_return(status: 200,
                   body: yaml_for("Adobe Publication adobe-glyph-list", "publication_slug" => "adobe-glyph-list"))
    end

    it "resolves by canonical slug form and scans the index (no number)" do
      item = described_class.get("Adobe Publication adobe-glyph-list")
      expect(item.docidentifier.first.content).to eq "Adobe Publication adobe-glyph-list"
      # a publication has no number, so nil is passed -> full scan, not narrowing
      expect(search_args.last).to be_nil
    end
  end

  context "errors and soft misses" do
    it "raises RequestError on a non-200 response" do
      stub_index([row("Adobe Technical Note #5014", "data/5014.yaml")])
      stub_request(:get, "#{described_class::ENDPOINT}data/5014.yaml")
        .to_return(status: 404, body: "Not Found")
      expect { described_class.get("ATN5014") }.to raise_error(Relaton::RequestError)
    end

    it "returns nil (not a parse error) for an unparseable Adobe reference" do
      stub_index([])
      expect { described_class.get("Adobe Glyph List") }.not_to raise_error
      expect(described_class.get("Adobe Glyph List")).to be_nil
    end
  end
end
