# frozen_string_literal: true

RSpec.describe Relaton::ThreeGpp do
  it "has a version number" do
    expect(Relaton::VERSION).not_to be nil
  end

  it "returs grammar hash" do
    hash = Relaton::ThreeGpp.grammar_hash
    expect(hash).to be_instance_of String
    expect(hash.size).to eq 32
  end

  context "get document" do
    let(:bib) do
      VCR.use_cassette "3gpp_get_document" do
        Relaton::ThreeGpp::Bibliography.get "3GPP TR 00.01U:UMTS/3.0.0"
      end
    end

    before do |example|
      next if example.metadata[:skip_before]

      # Force to download index file
      allow_any_instance_of(Relaton::Index::Type).to receive(:actual?).and_return(false)
      allow_any_instance_of(Relaton::Index::FileIO).to receive(:check_file).and_return(nil)
    end

    it "returns bibliographic item" do
      expect(bib).to be_instance_of Relaton::ThreeGpp::ItemData
    end

    it "render XML" do
      file = "fixtures/bib.xml"
      expect { bib }.to output(
        %r{\[relaton-3gpp\]\sINFO:\s\(3GPP\sTR\s00.01U:UMTS/3\.0\.0\)\sFound:\s`3GPP\sTR\s00.01U:UMTS/3.0.0`}x,
      ).to_stderr_from_any_process
      xml = bib.to_xml
      File.write file, xml, encoding: "UTF-8" unless File.exist? file
      expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
        .sub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s)
      schema = Jing.new "../../grammar/relaton-3gpp-compile.rng"
      errors = schema.validate file
      expect(errors).to eq []
    end

    it "render XML with ext element" do
      file = "fixtures/bibdata.xml"
      xml = bib.to_xml bibdata: true
      File.write file, xml, encoding: "UTF-8" unless File.exist? file
      expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
        .sub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s)
      schema = Jing.new "../../grammar/relaton-3gpp-compile.rng"
      errors = schema.validate file
      expect(errors).to eq []
    end

    it "render YAML" do
      file = "fixtures/bib.yaml"
      hash = YAML.load bib.to_yaml
      expect(hash["fetched"]).to match(/^\d{4}-\d{2}-\d{2}$/)
      hash.delete("fetched")
      File.write file, hash.to_yaml, encoding: "UTF-8"
      yaml = YAML.load_file(file)
      yaml.delete("fetched")
      expect(hash).to be_equivalent_to yaml
    end
  end

  # A parseable reference that is simply absent from the index: a miss, and
  # the cache stores a `not_found` marker for it. (`3GPP 1234` used to stand
  # here, but it does not parse at all — see the next example.)
  it "document not found" do
    expect do
      expect(Relaton::ThreeGpp::Bibliography.get("3GPP TS 99.999")).to be_nil
    end.to output(/\[relaton-3gpp\] INFO: \(3GPP TS 99\.999\) Not found/).to_stderr_from_any_process
  end

  # Mirrors ISO and ETSI: an unrecognized reference raises rather than
  # returning nil, so relaton-cli can render "… is not a recognized standards
  # identifier". `Parslet::ParseFailed` is the class the CLI rescues.
  it "raises on an unrecognized reference" do
    expect { Relaton::ThreeGpp::Bibliography.get("3GPP 1234") }
      .to raise_error Parslet::ParseFailed
  end
end
