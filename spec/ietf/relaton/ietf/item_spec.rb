describe Relaton::Ietf::Item do
  let(:input_yaml) { File.read "fixtures/item.yaml", encoding: "UTF-8" }
  let(:input_hash) { YAML.safe_load input_yaml }
  let(:item) { described_class.from_yaml input_yaml }
  let(:output_hash) { YAML.safe_load described_class.to_yaml(item) }

  it "round trip" do
    expect(output_hash).to eq input_hash
  end

  it "adds IETF to the primary docidentifier in the external form only" do
    docid = item.docidentifier.first
    expect(docid.to_s(form: :external)).to eq "IETF RFC 8341"
    expect(docid.to_s(form: :internal)).to eq "RFC 8341"
  end

  it "renders the forms of an Internet-Draft" do
    docid = Relaton::Bib::Docidentifier.new(type: "Internet-Draft", content: "draft-ietf-netconf-x-01")
    expect(docid.to_s(form: :external)).to eq "IETF Internet-Draft draft-ietf-netconf-x-01"
    expect(docid.to_s(form: :internal)).to eq "Internet-Draft draft-ietf-netconf-x-01"
  end
end
