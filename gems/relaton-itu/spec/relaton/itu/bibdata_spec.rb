describe Relaton::Itu::Bibdata do
  let(:file) { "spec/fixtures/bibdata.xml" }
  let(:input_xml) { File.read file, encoding: "UTF-8" }
  let(:item) { described_class.from_xml input_xml }

  it "round trip" do
    expect(item.to_xml(bibdata: true)).to be_equivalent_to input_xml
    schema = Jing.new "spec/schemas/relaton-itu-compile.rng"
    errors = schema.validate file
    expect(errors).to eq []
  end
end
