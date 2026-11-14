RSpec.describe Relaton::Bibcollection do
  describe ".from_xml" do
    it "instantiate a new collection from xml" do
      document = Relaton::Bibcollection.from_xml(
        Nokogiri.XML(File.read("spec/fixtures/sample-collection.xml")),
      )

      expect(document.title).to eq("CalConnect Standards Registry")
      expect(document.author).to eq("The Calendaring and Scheduling Consortium")
      expect(document.items[0].title[0].content).to include("Date and time -- Concepts")
      expect(document.items[1].title[0].content).to include("Date and time -- Timezones")
    end

    it "handle empty XML" do
      document = Relaton::Bibdata.from_xml Nokogiri::XML("")
      expect(document).to be_nil
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
  end
end
