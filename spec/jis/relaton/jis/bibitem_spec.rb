describe Relaton::Jis::Bibitem do
  let(:file) { "fixtures/bibitem.xml" }
  let(:input_xml) { File.read file, encoding: "UTF-8" }
  let(:item) { described_class.from_xml input_xml }

  it "rounds trip" do
    expect(described_class.to_xml(item)).to be_equivalent_to input_xml
    schema = Jing.new "../../grammar/relaton-jis-compile.rng"
    errors = schema.validate file
    expect(errors).to eq []
  end
end
