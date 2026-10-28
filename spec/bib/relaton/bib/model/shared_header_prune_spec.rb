# The shared Item-header prunes must stay private to the pruning class.
# Under lutaml-model 0.8.142's copy-on-write inheritance, a class that has
# not run its own DSL shares mappings/attributes with its superclass — a
# fork-less delete erased Bibdata's :id from Bibitem (and Bibitem's :ext
# from Bibdata), so every from_xml raised "Attribute ... not found".
require "relaton/bib"
require "equivalent-xml/rspec_matchers"

RSpec.describe "Relaton::Bib shared-header attribute prunes" do
  it "keeps the pruned attribute on sibling classes" do
    expect(Relaton::Bib::Bibitem.attributes).to be_key(:id)
    expect(Relaton::Bib::Bibitem.mappings[:xml].attributes.map(&:name))
      .to include("id")
    expect(Relaton::Bib::Bibdata.attributes).to be_key(:ext)
    expect(Relaton::Bib::Bibdata.mappings[:xml].elements.map(&:name))
      .to include("ext")
  end

  it "keeps the prune on the pruning classes" do
    expect(Relaton::Bib::Bibdata.attributes).not_to be_key(:id)
    expect(Relaton::Bib::Bibdata.mappings[:xml].attributes.map(&:name))
      .not_to include("id")
    expect(Relaton::Bib::Bibitem.attributes).not_to be_key(:ext)
    expect(Relaton::Bib::Bibitem.mappings[:xml].elements.map(&:name))
      .not_to include("ext")
  end

  it "round-trips the pruned shapes" do
    bibdata_xml = <<~XML
      <bibdata type="standard" schema-version="v1.5.6">
        <title type="main" language="en" format="text/plain">Probe</title>
        <docidentifier type="ISO">ISO 1:2020</docidentifier>
        <docnumber>1</docnumber>
        <date type="published"><on>2020-01</on></date>
        <contributor>
          <role type="publisher"/>
          <organization><name>ISO</name></organization>
        </contributor>
        <ext><doctype>standard</doctype></ext>
      </bibdata>
    XML
    bibitem_xml = <<~XML
      <bibitem id="iso1" type="standard" schema-version="v1.5.6">
        <title type="main" language="en" format="text/plain">Probe</title>
        <docidentifier type="ISO">ISO 1:2020</docidentifier>
        <docnumber>1</docnumber>
        <date type="published"><on>2020-01</on></date>
        <contributor>
          <role type="publisher"/>
          <organization><name>ISO</name></organization>
        </contributor>
      </bibitem>
    XML
    bibdata = Relaton::Bib::Bibdata.from_xml(bibdata_xml)
    bibitem = Relaton::Bib::Bibitem.from_xml(bibitem_xml)
    expect(Relaton::Bib::Bibdata.to_xml(bibdata)).to be_equivalent_to(bibdata_xml)
    expect(Relaton::Bib::Bibitem.to_xml(bibitem)).to be_equivalent_to(bibitem_xml)
  end
end
