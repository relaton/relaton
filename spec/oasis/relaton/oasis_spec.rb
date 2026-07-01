# frozen_string_literal: true

RSpec.describe Relaton::Oasis do
  before do |example|
    next unless example.metadata[:vcr]

    # Force to download index file
    allow_any_instance_of(Relaton::Index::Type).to receive(:actual?).and_return(false)
    allow_any_instance_of(Relaton::Index::FileIO).to receive(:check_file).and_return(nil)
  end

  it "has a version number" do
    expect(Relaton::Oasis::VERSION).not_to be_nil
  end

  it "return grammar hash" do
    hash = described_class.grammar_hash
    expect(hash).to be_instance_of String
    expect(hash.size).to eq 32
  end

  it "get document", vcr: "oasis_bib" do
    expect do
      ref = "OASIS AkomaNtosoCore-v1.0-Pt1-Vocabulary"
      item = Relaton::Oasis::Bibliography.search ref
      xml = item.to_xml(bibdata: true)
      file = "fixtures/document.xml"
      File.write file, xml, encoding: "UTF-8" unless File.exist? file
      expect(item).to be_instance_of Relaton::Oasis::ItemData
      expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
        .gsub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}(?=<\/fetched>)/, Date.today.to_s)
      schema = Jing.new "../../grammar/relaton-oasis-compile.rng"
      errors = schema.validate file
      expect(errors).to eq []
    end.to output(
      include("Fetching from Relaton repository",
              "Found: `OASIS AkomaNtosoCore-v1.0-Pt1-Vocabulary`"),
    ).to_stderr_from_any_process
  end

  it "not found" do
    expect do
      resp = Relaton::Oasis::Bibliography.search "invalid"
      expect(resp).to be_nil
    end.to output(
      /\[relaton-oasis\] INFO: \(invalid\) Not found\./,
    ).to_stderr_from_any_process
  end
end
