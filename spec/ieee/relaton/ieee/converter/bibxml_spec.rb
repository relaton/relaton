require "relaton/ieee/data_fetcher"

RSpec.describe Relaton::Ieee::Converter::BibXml do
  describe ".to_item" do
    context "with a reference XML" do
      let(:xml) { File.read("fixtures/bibxml.xml") }

      it "returns an ItemData" do
        result = described_class.to_item(xml)
        expect(result).to be_a Relaton::Ieee::ItemData
      end

      it "parses the title" do
        result = described_class.to_item(xml)
        expect(result.title.first.content).to include "IEEE Standard for Inertial Sensor Terminology"
      end

      it "parses the docidentifier" do
        result = described_class.to_item(xml)
        ids = result.docidentifier.map(&:content)
        expect(ids).to include "IEEE 528-2019"
      end
    end

    context "with a referencegroup XML" do
      let(:xml) do
        <<~XML
          <referencegroup anchor="IEEE.STD-GROUP">
            <reference anchor="IEEE.1-2020">
              <front>
                <title>First Standard</title>
              </front>
            </reference>
            <reference anchor="IEEE.2-2020">
              <front>
                <title>Second Standard</title>
              </front>
            </reference>
          </referencegroup>
        XML
      end

      it "returns an ItemData" do
        result = described_class.to_item(xml)
        expect(result).to be_a Relaton::Ieee::ItemData
      end

      it "has relations from child references" do
        result = described_class.to_item(xml)
        expect(result.relation).not_to be_empty
      end
    end
  end
end
