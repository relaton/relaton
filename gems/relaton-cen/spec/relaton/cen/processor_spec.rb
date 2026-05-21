require "relaton/cen/processor"

describe Relaton::Cen::Processor do
  it "#intialize" do
    expect(subject.instance_variable_get(:@short)).to eq :relaton_cen
    expect(subject.instance_variable_get(:@prefix)).to eq "CEN"
    expect(subject.instance_variable_get(:@defaultprefix)).to eq(/^(C?EN|ENV|CWA|HD|CR)[\s\/]/)
    expect(subject.instance_variable_get(:@idtype)).to eq "CEN"
  end

  it "#get" do
    expect(Relaton::Cen::Bibliography).to receive(:get).with("19115", "2014", {})
    subject.get "19115", "2014", {}
  end

  it "#from_xml" do
    expect(Relaton::Cen::Item).to receive(:from_xml).with("<xml></xml>")
    subject.from_xml "<xml></xml>"
  end

  it "#from_yaml" do
    expect(Relaton::Cen::Item).to receive(:from_yaml).with("---\nkey: value\n")
    subject.from_yaml "---\nkey: value\n"
  end

  it "#grammar_hash" do
    expect(subject.grammar_hash).to be_a String
  end
end
