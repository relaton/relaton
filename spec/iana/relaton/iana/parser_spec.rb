require "relaton/iana/data_fetcher"

RSpec.describe Relaton::Iana::Parser do
  it "initialize" do
    expect(described_class).to receive(:new).with(nil, nil, {}).and_call_original
    expect(described_class.parse(nil)).to be_nil
  end

  context "instance" do
    let(:xml) { Nokogiri::XML File.read("fixtures/rpki.xml", encoding: "UTF-8") }

    subject do
      described_class.new xml.at("/xmlns:registry"), nil
    end

    it "parse" do
      bib = subject.parse
      xml = bib.to_xml bibdata: true
      file = "fixtures/rpki_bib.xml"
      File.write file, xml, encoding: "UTF-8" unless File.exist? file
      expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
    end

    it "replace slash in anchor" do
      doc = xml.at "/xmlns:registry"
      root_doc = described_class.parse doc
      registry = doc.at "./xmlns:registry"
      parser = described_class.new registry, root_doc
      expect(parser.anchor).to eq "RPKI__SIGNED-OBJECTS"
    end
  end
end
