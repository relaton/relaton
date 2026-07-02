require "relaton/ecma/data_fetcher"

describe Relaton::Ecma::ParserCommon do
  # Use DataParser as a concrete class that includes ParserCommon
  let(:parser) { Relaton::Ecma::DataParser.new(hit) }
  let(:hit) do
    Nokogiri::HTML(
      '<a href="https://ecma-international.org/publications-and-standards/standards/ecma-370/">ECMA-370</a>'
    ).at("a")
  end

  it "#contributor" do
    contrib = parser.contributor

    expect(contrib).to be_instance_of Array
    expect(contrib.size).to eq 1
    expect(contrib.first).to be_instance_of Relaton::Bib::Contributor
    expect(contrib.first.organization).to be_instance_of Relaton::Bib::Organization
    expect(contrib.first.organization.name.first.content).to eq "Ecma International"
    expect(contrib.first.role.first.type).to eq "publisher"
  end

  it "#fetch_docidentifier" do
    docid = parser.fetch_docidentifier("ECMA-6")
    expect(docid.first).to be_instance_of Relaton::Bib::Docidentifier
    expect(docid.first.type).to eq "ECMA"
    expect(docid.first.content).to eq "ECMA-6"
  end

  it "#fetch_doctype" do
    doctype = parser.fetch_doctype
    expect(doctype).to be_instance_of Relaton::Bib::Doctype
    expect(doctype.content).to eq "document"
  end
end
