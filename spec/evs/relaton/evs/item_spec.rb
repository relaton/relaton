# frozen_string_literal: true

describe Relaton::Evs::Item do
  let(:input_yaml) { File.read "fixtures/item.yaml", encoding: "UTF-8" }
  let(:input_hash) { YAML.safe_load input_yaml }
  let(:item) { described_class.from_yaml input_yaml }
  let(:output_hash) { YAML.safe_load described_class.to_yaml(item) }

  it "round trip" do
    expect(output_hash).to eq input_hash
  end

  it "keeps the document identity through the round trip" do
    expect(item.docidentifier.first.content).to eq "EVS-EN 18216:2026"
    expect(output_hash.dig("docidentifier", 0, "content")).to eq "EVS-EN 18216:2026"
  end
end
