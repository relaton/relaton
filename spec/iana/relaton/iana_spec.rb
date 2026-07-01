# frozen_string_literal: true

RSpec.describe Relaton::Iana do
  before do |example|
    unless example.metadata[:skip_before]
      # Force to download index file
      allow_any_instance_of(Relaton::Index::Type).to receive(:actual?).and_return(false)
      allow_any_instance_of(Relaton::Index::FileIO).to receive(:check_file).and_return(nil)
    end
  end

  it "has a version number" do
    expect(Relaton::Iana::VERSION).not_to be nil
  end

  it "returs grammar hash" do
    hash = Relaton::Iana.grammar_hash
    expect(hash).to be_instance_of String
    expect(hash.size).to eq 32
  end

  it "get document", vcr: "auto-response-parameters" do
    expect do
      bib = Relaton::Iana::Bibliography.get "IANA auto-response-parameters"
      xml = bib.to_xml bibdata: true
      file = "fixtures/auto-response-parameters.xml"
      File.write file, xml, encoding: "UTF-8" unless File.exist? file
      expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
        .sub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}(?=<\/fetched>)/, Date.today.to_s)
      schema = Jing.new "../../grammar/relaton-iana-compile.rng"
      errors = schema.validate file
      expect(errors).to eq []
    end.to output(
      include(
        "[relaton-iana] INFO: (IANA auto-response-parameters) Fetching from Relaton repository ...",
        "[relaton-iana] INFO: (IANA auto-response-parameters) Found: `IANA auto-response-parameters`",
      ),
    ).to_stderr_from_any_process
  end

  it "not found document", skip_before: true do
    expect do
      bib = Relaton::Iana::Bibliography.get "IANA Link Relation Types"
      expect(bib).to be_nil
    end.to output(/\[relaton-iana\] INFO: \(IANA Link Relation Types\) Not found\./).to_stderr_from_any_process
  end
end
