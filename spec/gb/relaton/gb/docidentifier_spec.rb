# frozen_string_literal: true

RSpec.describe Relaton::Gb::Docidentifier do
  def docid(content)
    described_class.new(content: content, type: "Chinese Standard", primary: true)
  end

  # content => [after remove_part!, after remove_date!, after to_all_parts!]
  {
    "GB/T 20223-2006" => ["GB/T 20223-2006", "GB/T 20223", "GB/T 20223 (all parts)"],
    "GB/T 5606.1-2004" => ["GB/T 5606-2004", "GB/T 5606.1", "GB/T 5606 (all parts)"],
    "JB/T 13368-2018" => ["JB/T 13368-2018", "JB/T 13368", "JB/T 13368 (all parts)"],
    "GB 2312-1980" => ["GB 2312-1980", "GB 2312", "GB 2312 (all parts)"],
    "GB/Z 1234-2020" => ["GB/Z 1234-2020", "GB/Z 1234", "GB/Z 1234 (all parts)"],
    "T/GZAEPI 001-2018" => ["T/GZAEPI 001-2018", "T/GZAEPI 001", "T/GZAEPI 001 (all parts)"],
    "GB/T 5606 (all parts)" => ["GB/T 5606 (all parts)", "GB/T 5606 (all parts)",
                                "GB/T 5606 (all parts)"],
  }.each do |content, (no_part, no_date, all_parts)|
    context content do
      it "parses the content into a pubid" do
        expect(docid(content).pubid).to be_a Pubid::Gb::Identifier
      end

      it "removes the part" do
        id = docid(content)
        id.remove_part!
        expect(id.content).to eq no_part
      end

      it "removes the date" do
        id = docid(content)
        id.remove_date!
        expect(id.content).to eq no_date
      end

      it "converts to all parts" do
        id = docid(content)
        id.to_all_parts!
        expect(id.content).to eq all_parts
      end
    end
  end

  context "with a value that is not a GB identifier" do
    let(:content) { "ISBN 978-0-00-000000-0" }

    it "keeps the content verbatim and has no pubid" do
      id = docid(content)
      expect(id.pubid).to be_nil
      id.remove_part!
      id.remove_date!
      id.to_all_parts!
      expect(id.content).to eq content
    end
  end

  it "keeps the parsed all-parts form through an XML round trip" do
    item = Relaton::Gb::Item.from_xml File.read("fixtures/gbt_5606_2004_all_parts.xml", encoding: "UTF-8")
    expect(item.docidentifier.first.content).to eq "GB/T 5606 (all parts)"
    expect(item.docidentifier.first.pubid.all_parts).to be true
  end
end
