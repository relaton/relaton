describe Relaton::Sae::Item do
  let(:yaml) do
    File.read "fixtures/data/sae-j3016_202104.yaml", encoding: "UTF-8"
  end
  let(:item) { described_class.from_yaml yaml }

  it "round-trips YAML" do
    expect(described_class.to_yaml(item)).to eq yaml
  end

  it "writes bibdata XML that the SAE grammar accepts" do
    Dir.mktmpdir do |dir|
      file = File.join dir, "bibdata.xml"
      File.write file, Relaton::Sae::Bibdata.to_xml(item), encoding: "UTF-8"
      expect(Relaxng.new("../../grammar/relaton-sae-compile.rng").validate(file)).to eq []
    end
  end

  it "writes bibitem XML that the SAE grammar accepts" do
    Dir.mktmpdir do |dir|
      file = File.join dir, "bibitem.xml"
      File.write file, Relaton::Sae::Bibitem.to_xml(item), encoding: "UTF-8"
      expect(Relaxng.new("../../grammar/relaton-sae-compile.rng").validate(file)).to eq []
    end
  end
end
