RSpec.describe Relaton::Bibcollection do
  let(:sample) { File.read("spec/fixtures/sample-collection.xml") }

  # A one-item collection; `extra` goes after the title.
  def coll_xml(title, extra = "", root: '<relaton-collection xmlns="https://open.ribose.com/relaton-xml">')
    "#{root}<title>#{title}</title>#{extra}<relation type=\"partOf\">" \
      "<bibdata type=\"standard\"><title>Item</title>" \
      "<docidentifier type=\"CC\" primary=\"true\">CC 18001</docidentifier>" \
      "</bibdata></relation></relaton-collection>"
  end

  describe ".from_xml" do
    it "instantiate a new collection from xml" do
      document = Relaton::Bibcollection.from_xml(Nokogiri.XML(sample))

      expect(document.title).to eq("CalConnect Standards Registry")
      expect(document.author).to eq("The Calendaring and Scheduling Consortium")
      expect(document.items[0].title[0].content).to include("Date and time -- Concepts")
      expect(document.items[1].title[0].content).to include("Date and time -- Timezones")
    end

    it "reads an XML string" do
      document = described_class.from_xml sample
      expect(document.title).to eq "CalConnect Standards Registry"
      expect(document.author).to eq "The Calendaring and Scheduling Consortium"
      expect(document.items.size).to eq 6
      expect(document.items).to all be_a Relaton::Bibdata
    end

    it "reads a collection with no namespace" do
      document = described_class.from_xml sample.sub(/ xmlns="[^"]+"/, "")
      expect(document.title).to eq "CalConnect Standards Registry"
      expect(document.items.size).to eq 6
    end

    it "reads a nested collection" do
      xml = File.read("spec/assets/with-collections.xml")
      inner = coll_xml("Inner", root: "<relaton-collection>")
      xml = xml.sub("</relaton-collection>",
                    "<relation type=\"partOf\">#{inner}</relation></relaton-collection>")
      document = described_class.from_xml xml
      nested = document.items.grep(described_class)
      expect(nested.size).to eq 1
      expect(nested.first.title).to eq "Inner"
      expect(nested.first.items.first.docidentifier).to eq "CC 18001"
    end

    it "keeps the markup of a title" do
      document = described_class.from_xml coll_xml("A <em>b</em> c")
      expect(document.title).to eq "A <em>b</em> c"
    end

    it "reads the doctype" do
      document = described_class.from_xml(
        coll_xml("T", root: '<relaton-collection type="ISO">'),
      )
      expect(document.doctype).to eq "ISO"
    end

    it "reads a collection with no items" do
      document = described_class.from_xml "<relaton-collection><title>T</title></relaton-collection>"
      expect(document.items).to eq []
    end

    it "handle empty XML" do
      document = Relaton::Bibdata.from_xml Nokogiri::XML("")
      expect(document).to be_nil
    end
  end

  describe "#to_xml" do
    it "writes the collection in the relaton-xml namespace" do
      xml = described_class.from_xml(sample).to_xml(bibdata: true)
      expect(xml).to start_with '<relaton-collection xmlns="https://open.ribose.com/relaton-xml"'
      expect(xml).not_to include 'xmlns=""'
      expect(xml.scan("<relation type=\"partOf\">").size).to eq 6
    end

    it "round-trips title, author, doctype and items" do
      coll = described_class.from_xml(
        coll_xml("A &amp; <em>b</em>",
                 "<contributor><role type=\"author\"/><organization><name>Org &amp; Co" \
                 "</name></organization></contributor>",
                 root: '<relaton-collection type="ISO">'),
      )
      read = described_class.from_xml coll.to_xml(bibdata: true)
      expect(read.title).to eq "A &amp; <em>b</em>"
      expect(read.author).to eq "Org &amp; Co"
      expect(read.doctype).to eq "ISO"
      expect(read.items.map(&:docidentifier)).to eq ["CC 18001"]
    end

    it "escapes a bare ampersand in a title from YAML" do
      coll = described_class.new("title" => "A & B", "author" => "X & Y", "items" => [])
      xml = coll.to_xml
      expect(xml).to include "<title>A &amp; B</title>"
      expect(xml).to include "<name>X &amp; Y</name>"
      expect(described_class.from_xml(xml).title).to eq "A &amp; B"
    end

    it "round-trips a nested collection" do
      inner = described_class.from_xml coll_xml("Inner")
      outer = described_class.new("title" => "Outer", "items" => [inner])
      read = described_class.from_xml outer.to_xml(bibdata: true)
      expect(read.items.first).to be_a described_class
      expect(read.items.first.title).to eq "Inner"
      expect(read.items.first.items.map(&:docidentifier)).to eq ["CC 18001"]
    end

    it "reads the author among several contributors, and the first title" do
      coll = described_class.from_xml(
        coll_xml("T1</title><title>T2",
                 "<contributor><role type=\"publisher\"/><organization><name>P</name>" \
                 "</organization></contributor><contributor><role type=\"author\"/>" \
                 "<organization><name>A</name></organization></contributor>"),
      )
      expect(coll.title).to eq "T1"
      expect(coll.author).to eq "A"
    end

    it "keeps foreign namespaces in markup, and escapes an HTML entity" do
      math = '<math xmlns="http://www.w3.org/1998/Math/MathML"><mi>x</mi></math>'
      coll = described_class.new("title" => "T <stem>#{math}</stem> a&nbsp;b", "items" => [])
      doc = Nokogiri::XML(coll.to_xml)
      title = doc.at("/xmlns:relaton-collection/xmlns:title")
      ns = { "r" => "https://open.ribose.com/relaton-xml",
             "m" => "http://www.w3.org/1998/Math/MathML" }
      expect(title.at("./r:stem/m:math/m:mi", ns).text).to eq "x"
      expect(title.text).to end_with " a&nbsp;b"
    end

    it "writes each item's XML as the item writes it" do
      coll = described_class.from_xml sample
      item = coll.items.first
      allow(item).to receive(:to_xml).and_return(
        '<bibdata xmlns:xlink="http://www.w3.org/1999/xlink"><title xml:lang="en">' \
        "A <em>b</em><!-- c --></title><uri xlink:href=\"u\"/></bibdata>",
      )
      coll.items.replace [item]
      doc = Nokogiri::XML(coll.to_xml)
      bib = doc.at("//xmlns:relation/xmlns:bibdata")
      expect(bib.at("./xmlns:title").inner_html).to eq "A <em>b</em><!-- c -->"
      expect(bib.at("./xmlns:title")["xml:lang"]).to eq "en"
      expect(bib.at("./xmlns:uri").attribute_with_ns("href", "http://www.w3.org/1999/xlink").value)
        .to eq "u"
    end

    it "keeps the item XML of the old serializer" do
      coll = described_class.from_xml sample
      old = Nokogiri::XML(coll.items.first.to_xml(bibdata: true))
      new = Nokogiri::XML(coll.to_xml(bibdata: true)).remove_namespaces!
      expect(new.at("//relation/bibdata").to_xml.gsub(/\s+/, ""))
        .to eq old.root.to_xml.gsub(/\s+/, "")
    end
  end

  describe "#to_h" do
    it "round-trips a nested collection" do
      inner = described_class.new(
        "title" => "Inner", "items" => [{
          "id" => "CC18001", "docidentifier" =>
          [{ "type" => "CC", "content" => "CC 18001", "primary" => true }]
        }]
      )
      outer = described_class.new("title" => "Outer", "items" => [inner])
      read = described_class.new YAML.safe_load(outer.to_yaml)["root"]
      expect(read.items.first).to be_a described_class
      expect(read.items.first.title).to eq "Inner"
      expect(read.items.first.items.map { |i| i.docidentifier.to_s })
        .to eq ["CC 18001"]
    end

    it "takes symbol keys" do
      coll = described_class.new(title: "T", author: "A", doctype: "D", items: [])
      expect(coll.to_h).to eq(
        "root" => { "title" => "T", "items" => [], "doctype" => "D", "author" => "A" },
      )
    end
  end

  # relaton#459: the collection model reads and writes XML through
  # lutaml-model, not Nokogiri XPath and hand-joined strings.
  it "maps its XML with lutaml-model, with no Nokogiri" do
    expect(Relaton::CollectionXml).to be < Lutaml::Model::Serializable
    %w[bibcollection collection_xml].each do |f|
      src = File.read(File.expand_path("../../../lib/relaton/#{f}.rb", __dir__))
      expect(src).not_to match(/Nokogiri|ElementFinder/)
    end
    expect(defined?(Relaton::ElementFinder)).to be_nil
  end
end
