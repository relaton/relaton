RSpec.describe Relaton::Plateau::BibItem do
  let(:title) { RelatonBib::TypedTitleString.new(type: "main", content: "Title", language: "en", script: "Latn") }
  let(:docid) { Relaton::Plateau::Docidentifier.new(type: "PLATEAU", id: "id", parimary: true) }
  let(:doctype) { Relaton::Plateau::DocumentType.new(type: "Handbook") }
  let(:strid) { RelatonBib::StructuredIdentifier.new(type: "Handbook", agency: ["PLATEAU"], docnumber: "docnumber") }
  let(:stidcol) { RelatonBib::StructuredIdentifierCollection.new [strid] }
  let(:stagename) { Relaton::Plateau::Stagename.new(content: "stage name", abbreviation: "SN") }
  let(:cover) { Relaton::Plateau::Cover.new RelatonBib::Image.new(src: "image/src", mimetype: "image/jpeg") }

  subject do
    Relaton::Plateau::BibItem.new(
      title: [title], docid: [docid], doctype: doctype, subdoctype: "subdoctype",
      structuredidentifier: stidcol, stagename: stagename, cover: cover, filesize: 123
    )
  end

  it "creates bibitem" do
    expect(subject.title.first).to be title
    expect(subject.docidentifier.first).to be docid
    expect(subject.doctype).to be doctype
    expect(subject.subdoctype).to eq "subdoctype"
    expect(subject.structuredidentifier).to be stidcol
    expect(subject.stagename).to be stagename
    expect(subject.cover).to be cover
    expect(subject.filesize).to eq 123
  end

  context "to_xml" do
    it "bibitem" do
      builder = Nokogiri::XML::Builder.new
      subject.to_xml builder: builder
      expect(builder.doc.root.to_xml).to be_equivalent_to <<~XML
        <bibitem id="id" schema-version="v1.2.9">
          <title type="main" format="text/plain" language="en" script="Latn">Title</title>
          <docidentifier type="PLATEAU">id</docidentifier>
        </bibitem>
      XML
    end

    it "bibdata" do
      builder = Nokogiri::XML::Builder.new
      subject.to_xml builder: builder, bibdata: true
      expect(builder.doc.root.to_xml).to be_equivalent_to <<~XML
        <bibdata schema-version="v1.2.9">
          <title type="main" format="text/plain" language="en" script="Latn">Title</title>
          <docidentifier type="PLATEAU">id</docidentifier>
          <ext schema-version="v0.0.1">
            <doctype>Handbook</doctype>
            <subdoctype>subdoctype</subdoctype>
            <structuredidentifier type="Handbook">
              <agency>PLATEAU</agency>
              <docnumber>docnumber</docnumber>
            </structuredidentifier>
            <stagename abbreviation="SN">stage name</stagename>
            <cover>
              <image src="image/src" mimetype="image/jpeg"/>
            </cover>
            <filesize>123</filesize>
          </ext>
        </bibdata>
      XML
    end

    it "bibdata with nil values" do
      subject = Relaton::Plateau::BibItem.new title: [title], docid: [docid], doctype: doctype
      builder = Nokogiri::XML::Builder.new
      subject.to_xml builder: builder, bibdata: true
      expect(builder.doc.root.to_xml).to be_equivalent_to <<~XML
        <bibdata schema-version="v1.2.9">
          <title type="main" format="text/plain" language="en" script="Latn">Title</title>
          <docidentifier type="PLATEAU">id</docidentifier>
          <ext schema-version="v0.0.1">
            <doctype>Handbook</doctype>
          </ext>
        </bibdata>
      XML
    end
  end

  it "to_hash" do
    expect(subject.to_hash).to eq(
      "schema-version" => "v1.2.9", "id" => "id", "title" => [title.to_hash], "docid" => [docid.to_hash],
      "ext" => {
        "doctype" => doctype.to_hash,
        "subdoctype" => "subdoctype",
        "structuredidentifier" => [strid.to_hash],
        "stagename" => stagename.to_hash,
        "cover" => cover.to_hash,
        "filesize" => 123,
        "schema-version" => "v0.0.1"
      }
    )
  end

  it "to_asciibib" do
    expect(subject.to_asciibib).to eq <<~ASCIIBIB
      [%bibitem]
      == {blank}
      id:: id
      title.type:: main
      title.content:: Title
      title.language:: en
      title.script:: Latn
      title.format:: text/plain
      docid.type:: PLATEAU
      docid.id:: id
      doctype.type:: Handbook
      subdoctype:: subdoctype
      structured_identifier.docnumber:: docnumber
      structured_identifier.agency:: PLATEAU
      structured_identifier.type:: Handbook
      stagename.content:: stage name
      stagename.abbreviation:: SN
      cover.image.src:: image/src
      cover.image.mimetype:: image/jpeg
      filesize:: 123
    ASCIIBIB
  end
end
