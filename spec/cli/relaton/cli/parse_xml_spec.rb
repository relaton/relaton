# relaton#581: Cli.parse_xml reads the first docidentifier with Moxml, in any
# namespace, and hands lutaml-model a namespace-free copy of the tree.
RSpec.describe Relaton::Cli, ".parse_xml" do
  let(:ns) { "https://open.ribose.com/relaton-xml" }

  def bibdata(docid, root: "bibdata", attrs: "")
    <<~XML
      <#{root} #{attrs} type="standard">
        <fetched>2019-08-21</fetched>
        <title type="main" format="text/plain">Date and time</title>
        #{docid}
        <date type="published"><on>2018-10-17</on></date>
      </#{root}>
    XML
  end

  it "picks the processor by the docidentifier type in a namespaced bibdata" do
    docid = '<docidentifier primary="true" type="CC">CC 18001</docidentifier>'
    xml = bibdata(docid, attrs: %(xmlns="#{ns}"))
    item = described_class.parse_xml(xml)
    expect(item).to be_a Relaton::Calconnect::ItemData
    expect(item.docidentifier.first.content).to eq "CC 18001"
    expect(item.title.first.content).to eq "Date and time"
  end

  it "picks the processor by the docidentifier text when it has no type" do
    xml = bibdata("<docidentifier>CC 18001</docidentifier>")
    expect(described_class.parse_xml(xml)).to be_a Relaton::Calconnect::ItemData
  end

  it "reads a bibdata whose elements have a namespace prefix" do
    xml = <<~XML
      <x:bibdata xmlns:x="#{ns}" type="standard">
        <x:title xml:lang="en" format="text/plain">Date &amp; time</x:title>
        <x:docidentifier type="CC">CC 18001</x:docidentifier>
      </x:bibdata>
    XML
    item = described_class.parse_xml(xml)
    expect(item).to be_a Relaton::Calconnect::ItemData
    expect(item.docidentifier.first.content).to eq "CC 18001"
    # The title model keeps its content as markup, so `&` stays escaped.
    expect(item.title.first.content).to eq "Date &amp; time"
  end

  it "reads a relation bibitem in a default namespace" do
    xml = <<~XML
      <bibdata xmlns="https://open.ribose.com/standards/ietf" type="standard">
        <title>Base</title>
        <docidentifier type="CC">CC 18001</docidentifier>
        <relation type="updates">
          <bibitem type="standard">
            <title>Updated</title>
            <docidentifier type="CC">CC 18000</docidentifier>
          </bibitem>
        </relation>
      </bibdata>
    XML
    item = described_class.parse_xml(xml)
    expect(item.relation.first.bibitem.docidentifier.first.content)
      .to eq "CC 18000"
  end

  it "reads an unknown type as a plain bibliographic item" do
    xml = bibdata('<docidentifier type="NOSUCH">NOSUCH 1</docidentifier>')
    item = described_class.parse_xml(xml)
    expect(item).to be_instance_of Relaton::Bib::ItemData
    expect(item.docidentifier.first.content).to eq "NOSUCH 1"
  end

  it "keeps an undeclared entity reference as its text" do
    docid = '<docidentifier type="CC">CC 18001</docidentifier>'
    xml = bibdata(docid).sub("Date and time", "A&nbsp;B")
    expect(described_class.parse_xml(xml).title.first.content)
      .to eq "A&amp;nbsp;B"
  end

  it "keeps an attribute in no namespace over a prefixed one of its name" do
    docid = '<docidentifier type="CC">CC 18001</docidentifier>'
    xml = bibdata(docid).sub(
      '<title type="main"', '<title xmlns:a="urn:a" type="main" a:type="x"'
    )
    expect(described_class.parse_xml(xml).title.first.type).to eq "main"
  end

  it "answers nil for nil, an empty or a malformed source" do
    expect(described_class.parse_xml(nil)).to be_nil
    expect(described_class.parse_xml("")).to be_nil
    expect(described_class.parse_xml("<bibdata><title>")).to be_nil
  end

  it "does not use Nokogiri" do
    src = File.read File.expand_path("../../../../lib/relaton/cli.rb", __dir__)
    expect(src).not_to match(/Nokogiri|nokogiri/)
  end
end
