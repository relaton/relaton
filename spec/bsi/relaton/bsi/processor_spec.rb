require "relaton/bsi/processor"

describe Relaton::Bsi::Processor do
  it "#intialize" do
    expect(subject.instance_variable_get(:@short)).to eq :relaton_bsi
    expect(subject.instance_variable_get(:@prefix)).to eq "BSI"
    expect(subject.instance_variable_get(:@defaultprefix)).to eq %r{^(BSI|BS|PD)\s}
    expect(subject.instance_variable_get(:@idtype)).to eq "BSI"
  end

  it "#get" do
    expect(Relaton::Bsi::Bibliography).to receive(:get).with("BS EN ISO 8848", "2021", {})
    subject.get "BS EN ISO 8848", "2021", {}
  end

  it "#from_xml" do
    expect(Relaton::Bsi::Item).to receive(:from_xml).with("<xml></xml>")
    subject.from_xml "<xml></xml>"
  end

  it "#from_yaml" do
    expect(Relaton::Bsi::Item).to receive(:from_yaml).with("---\nkey: value\n")
    subject.from_yaml "---\nkey: value\n"
  end

  it "#grammar_hash" do
    expect(subject.grammar_hash).to be_a String
  end
end
