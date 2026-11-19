require "relaton/arxiv/processor"

describe Relaton::Arxiv::Processor do
  subject(:processor) { described_class.new }

  it "declares the flavor" do
    expect(processor.short).to eq :relaton_arxiv
    expect(processor.prefix).to eq "arXiv"
    expect(processor.idtype).to eq "arXiv"
    expect(processor.prefixes).to eq ["arXiv"]
    expect(processor.pubid_class).to be Pubid::Arxiv::Identifier
    expect(processor.defaultprefix).to match "arxiv:2301.00001"
  end

  it "parses a lower-case or bare reference" do
    expect(processor.cache_pubid("arxiv:2301.00001").to_s).to eq "arXiv:2301.00001"
    expect(processor.cache_pubid("arXiv 2301.00001v2").to_s).to eq "arXiv:2301.00001v2"
  end

  it "gives no pubid for a reference that is not an arXiv id" do
    expect(processor.cache_pubid("arXiv:not-an-id")).to be_nil
  end

  it "does not fold a year into the key: the id carries it" do
    key = processor.cache_key("arXiv:2301.00001", "1999", {})
    expect(key.to_s).to eq "arXiv:2301.00001"
  end

  it "delegates get to Bibliography" do
    expect(Relaton::Arxiv::Bibliography).to receive(:get).with("arXiv:1", nil, {}).and_return :item
    expect(processor.get("arXiv:1", nil, {})).to be :item
  end

  it "reads XML and YAML" do
    item = Relaton::Arxiv::Parser.parse File.read("fixtures/hep-th-9901001.xml")
    xml = Relaton::Bib::Bibitem.to_xml item
    expect(processor.from_xml(xml).docidentifier.first.content).to eq "arXiv:hep-th/9901001v3"
    hash = YAML.safe_load Relaton::Bib::Item.to_yaml(item)
    expect(processor.from_yaml(hash).docidentifier.first.content).to eq "arXiv:hep-th/9901001v3"
  end

  it "returns the grammar hash" do
    expect(processor.grammar_hash).to eq Digest::MD5.hexdigest(Relaton::VERSION)
  end
end
