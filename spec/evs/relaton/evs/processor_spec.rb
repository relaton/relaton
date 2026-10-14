# frozen_string_literal: true

require "relaton/evs/processor"
require "relaton/db"

describe Relaton::Evs::Processor do
  it "declares the registry attributes" do
    expect(subject.short).to eq :relaton_evs
    expect(subject.prefix).to eq "EVS"
    expect(subject.idtype).to eq "EVS"
  end

  it "sources its prefixes from Pubid::Evs" do
    expect(subject.prefixes).to include "EVS", "EVS-EN", "EVS-EN ISO",
                                        "EVS-EN ISO/IEC"
  end

  it "registers with the Db registry" do
    expect(Relaton::Db::Registry.instance.find_processor(:relaton_evs))
      .to be_a described_class
  end

  it "#get delegates to the Bibliography" do
    expect(Relaton::Evs::Bibliography).to receive(:get).with("EVS-EN 18216", "2026", {})
    subject.get "EVS-EN 18216", "2026", {}
  end

  it "#from_xml delegates to the Item" do
    expect(Relaton::Evs::Item).to receive(:from_xml).with("<xml></xml>")
    subject.from_xml "<xml></xml>"
  end

  it "#from_yaml delegates to the Item" do
    expect(Relaton::Evs::Item).to receive(:from_yaml).with("---\nkey: value\n")
    subject.from_yaml "---\nkey: value\n"
  end

  it "#grammar_hash derives from Relaton::VERSION" do
    require "digest/md5"
    expect(subject.grammar_hash)
      .to eq Digest::MD5.hexdigest(Relaton::VERSION)
  end
end
