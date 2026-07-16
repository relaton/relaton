# frozen_string_literal: true

require "relaton/db"
require "relaton/jcgm/processor"

RSpec.describe Relaton::Jcgm::Processor do
  subject(:processor) { described_class.new }

  it "declares JCGM prefix metadata" do
    expect(processor.short).to eq :relaton_jcgm
    expect(processor.prefix).to eq "JCGM"
    expect(processor.idtype).to eq "JCGM"
  end

  it "sources its prefixes from pubid" do
    expect(processor.prefixes).to eq ["JCGM"]
  end

  it "matches JCGM references with its default prefix" do
    dp = processor.instance_variable_get(:@defaultprefix)
    expect("JCGM 200:2012").to match dp
    expect("JCGM 17th Meeting (2012)").to match dp
    expect("BIPM CGPM 1").not_to match dp
  end

  it "deserializes a fixture record via from_yaml" do
    yaml = File.read(File.expand_path("../../fixtures/data/jcgm/meeting/17.yaml", __dir__),
                     encoding: "UTF-8")
    item = processor.from_yaml(yaml)
    expect(item).to be_a(Relaton::Jcgm::ItemData)
    expect(item.docnumber).to eq "JCGM 17th Meeting (2012)"
  end

  it "produces a 32-char grammar hash" do
    expect(processor.grammar_hash).to match(/\A[0-9a-f]{32}\z/)
  end

  describe "registry routing" do
    let(:registry) { Relaton::Db::Registry.instance }

    it "routes JCGM references to the jcgm flavor (not bipm)" do
      expect(registry.class_by_ref("JCGM 200:2012")).to eq :relaton_jcgm
      expect(registry.class_by_ref("JCGM 17th Meeting (2012)")).to eq :relaton_jcgm
    end

    it "still routes BIPM/CIPM references to the bipm flavor" do
      expect(registry.class_by_ref("CIPM 2019")).to eq :relaton_bipm
    end

    it "registers the jcgm processor" do
      expect(registry.processors).to have_key(:relaton_jcgm)
    end
  end
end
