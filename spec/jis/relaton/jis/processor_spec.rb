# frozen_string_literal: true

require "relaton/jis/processor"

describe Relaton::Jis::Processor do
  subject(:processor) { described_class.new }

  it "initializes" do
    expect(processor.short).to eq :relaton_jis
    expect(processor.prefix).to eq "JIS"
    expect(processor.defaultprefix).to eq %r{^(JIS|TR)\s}
    expect(processor.idtype).to eq "JIS"
    expect(processor.datasets).to eq %w[jis-webdesk]
  end

  it "#get" do
    expect(Relaton::Jis::Bibliography).to receive(:get)
      .with("JIS X 0208", nil, {}).and_return :item
    expect(processor.get("JIS X 0208", nil, {})).to eq :item
  end

  it "#from_xml" do
    xml = "<bibitem id='test'></bibitem>"
    expect(processor.from_xml(xml)).to be_instance_of Relaton::Jis::ItemData
  end

  it "#from_yaml" do
    yaml = "---\nid: test"
    expect(processor.from_yaml(yaml)).to be_instance_of Relaton::Jis::ItemData
  end

  it "#grammar_hash" do
    expect(processor.grammar_hash).to be_a String
    expect(processor.grammar_hash.size).to eq 32
  end

  it "#threads" do
    expect(processor.threads).to eq 3
  end
end
