require "relaton/oiml/processor"

RSpec.describe Relaton::Oiml::Processor do
  subject(:processor) { described_class.new }

  it "configures prefix matching" do
    expect(processor.short).to eq :relaton_oiml
    expect(processor.prefix).to eq "OIML"
    expect(processor.idtype).to eq "OIML"
    expect("OIML R 138").to match processor.defaultprefix
    expect("ISO 1234").not_to match processor.defaultprefix
  end

  it "gets a document", skip: "combined-bundle pubid from_hash regression (tracked)" do
    item = processor.get "OIML R 138", nil, {}
    expect(item).to be_instance_of Relaton::Oiml::ItemData
  end

  it "parses from YAML" do
    yaml = File.read "fixtures/data/r138_2007.yaml", encoding: "UTF-8"
    item = processor.from_yaml yaml
    expect(item).to be_instance_of Relaton::Oiml::ItemData
    expect(item.ext.quantity).to eq "Volume"
  end

  it "round-trips from XML" do
    yaml = File.read "fixtures/data/r138_2007.yaml", encoding: "UTF-8"
    xml = processor.from_yaml(yaml).to_xml(bibdata: true)
    item = processor.from_xml xml
    expect(item).to be_instance_of Relaton::Oiml::ItemData
    expect(item.docidentifier.first.content).to eq "OIML R 138:2007"
    # doctype + OIML ext fields survive a full-document XML round-trip
    expect(item.ext.doctype.content).to eq "recommendation"
    expect(item.ext.quantity).to eq "Volume"
    expect(item.ext.doi).to eq "10.63493/r138.2007.en"
  end

  it "returns a grammar hash" do
    expect(processor.grammar_hash).to be_instance_of String
  end
end
