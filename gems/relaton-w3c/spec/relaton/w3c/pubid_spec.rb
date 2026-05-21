# frozen_string_literal: true

require_relative "../../../lib/relaton/w3c/pubid"

RSpec.describe Relaton::W3c::PubId do
  describe "#to_s" do
    [
      "CRD-vibration-20260502",
      "NOTE-AS-19980619",
      "REC-xml-names-20091208",
      "WD-indexeddb-3-20230413",
      "PR-wai-autools-19991026",
      "xml-names",
    ].each do |docnumber|
      it "round-trips parse(#{docnumber.inspect}).to_s" do
        expect(described_class.parse(docnumber).to_s).to eq docnumber
      end
    end

    it "renders from hash-constructed parts" do
      pubid = described_class.new(code: "vibration", stage: "CRD", date: "20260502")
      expect(pubid.to_s).to eq "CRD-vibration-20260502"
    end

    it "renders bare code when only code is present" do
      expect(described_class.new(code: "atag10").to_s).to eq "atag10"
    end

    it "renders type prefix for NOTE without TR" do
      expect(described_class.new(code: "AS", type: "NOTE").to_s).to eq "NOTE-AS"
    end

    it "renders suff after a slash" do
      pubid = described_class.new(code: "css", stage: "REC", date: "20110607", suff: "errata")
      expect(pubid.to_s).to eq "REC-css-20110607/errata"
    end
  end
end
