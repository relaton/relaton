# frozen_string_literal: true

describe "ITU from_yaml round trip" do
  let(:file) { "fixtures/from_yaml.xml" }
  let(:item) { Relaton::Itu::Bibdata.from_xml File.read(file, encoding: "UTF-8") }

  it "round trip" do
    expect(Relaton::Itu::Bibdata.to_xml(item)).to be_equivalent_to File.read(file, encoding: "UTF-8")
  end

  it "validates against the ITU grammar" do
    schema = Relaxng.new "../../grammar/relaton-itu-compile.rng"
    expect(schema.validate(file)).to eq []
  end
end
