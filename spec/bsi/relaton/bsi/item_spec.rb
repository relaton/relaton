describe Relaton::Bsi::Item do
  let(:input_yaml) { File.read "fixtures/item.yaml", encoding: "UTF-8" }
  let(:input_hash) { YAML.safe_load input_yaml }
  let(:item) { described_class.from_yaml input_yaml }

  it "round trip" do
    output_hash = YAML.safe_load item.to_yaml
    expect(output_hash).to eq input_hash
  end

  it "to_json" do
    output_hash = JSON.parse item.to_json
    expect(output_hash).to eq input_hash
  end
end
