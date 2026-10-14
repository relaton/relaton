# frozen_string_literal: true

describe Relaton::Evs::Bibliography do
  # The designation-legend forms from evs.ee ("Standards designation"), over
  # the parse contract only — no network.
  describe ".parse" do
    it "parses a plain Estonian standard" do
      id = described_class.parse "EVS 945:2023"
      expect(id).to be_a Pubid::Evs::Identifiers::EstonianStandard
      expect(id.to_s).to eq "EVS 945:2023"
      expect(id.root.number).to eq "945"
      expect(id.root.year).to eq "2023"
    end

    it "parses the TS and TR faces" do
      expect(Pubid::Evs.parse("EVS-TS 1:2019").evs_type).to eq "TS"
      expect(Pubid::Evs.parse("EVS 945:2023").root.number).to eq "945"
    end

    it "parses a national adoption of a European standard" do
      id = described_class.parse "EVS-EN 18216:2026"
      expect(id).to be_a Pubid::Evs::Identifiers::NationalAdoption
      expect(id.base.to_s).to eq "EN 18216:2026"
      expect(id.root.number).to eq "18216"
    end

    it "parses a national adoption through the EN ISO chain" do
      id = described_class.parse "EVS-EN ISO 9001:2015"
      expect(id.base.to_s).to eq "EN ISO 9001:2015"
      expect(id.base.adopted.to_s).to eq "ISO 9001:2015"
      expect(id.root.number).to eq "9001"
      expect(id.root.year).to eq "2015"
    end

    it "parses a national adoption of an amendment" do
      id = described_class.parse "EVS-EN ISO 9001:2015/A1:2024"
      expect(id.root.number).to eq "9001"
      expect(id.root.year).to eq "2015"
      expect(id.to_urn).to eq "urn:evs:en:iso:9001:2015:amd:1:2024"
    end

    it "parses the ISO/IEC joint adoption" do
      id = described_class.parse "EVS-EN ISO/IEC 27017:2026"
      expect(id.base.to_s).to eq "EN ISO/IEC 27017:2026"
      expect(id.to_urn).to eq "urn:evs:en:iso-iec:27017:2026"
    end

    it "parses direct international adoptions" do
      iso = described_class.parse "EVS-ISO 9001:2015"
      expect(iso).to be_a Pubid::Evs::Identifiers::InternationalAdoption
      expect(iso.intl_org).to eq "ISO"

      iec = described_class.parse "EVS-IEC 62368-1:2020"
      expect(iec.intl_org).to eq "IEC"
      expect(iec.part).to eq "1"
    end

    it "parses the space prefix form to the same identifier" do
      space = described_class.parse "EVS EN 18216:2026"
      hyphen = described_class.parse "EVS-EN 18216:2026"
      expect(space.class).to eq hyphen.class
      expect(space.root.number).to eq hyphen.root.number
      # The printed separator is identity: each renders back as written.
      expect(space.to_s).to eq "EVS EN 18216:2026"
      expect(hyphen.to_s).to eq "EVS-EN 18216:2026"
    end

    it "parses supplements and national annexes" do
      expect(described_class.parse("EVS-EN 50581:2012+COR:2015").to_s)
        .to eq "EVS-EN 50581:2012+COR:2015"
      expect(described_class.parse("EVS-EN 1993-1-1:2005+NA:2010").to_s)
        .to eq "EVS-EN 1993-1-1:2005+NA:2010"
      expect(described_class.parse("EVS-EN 1993-1-1:2005/NA").to_s)
        .to eq "EVS-EN 1993-1-1:2005/NA"
    end

    it "parses draft designations" do
      expect(described_class.parse("prEVS-EN 18216:2026").to_s)
        .to eq "prEVS-EN 18216:2026"
    end

    it "parses language codes" do
      expect(described_class.parse("EVS 811:2018 et").language).to eq "et"
      expect(described_class.parse("EVS-EN 18216:2026 en").language).to eq "en"
      expect(described_class.parse("EVS 811:2018 et-en").language).to eq "et-en"
    end

    it "raises on a reference the grammar cannot read" do
      expect { described_class.parse "ISO 9001" }
        .to raise_error Pubid::Errors::ParseError
    end
  end

  describe ".get" do
    it "returns nil for an empty reference" do
      expect(described_class.get("")).to be_nil
      expect(described_class.get(nil)).to be_nil
    end

    context "with a national adoption", vcr: { cassette_name: "evs_en_18216_2026" } do
      it "fetches the record" do
        bib = described_class.get "EVS-EN 18216:2026"
        expect(bib).to be_a Relaton::Evs::ItemData
        expect(bib.docidentifier.first.content).to eq "EVS-EN 18216:2026"
        expect(bib.docidentifier.first.type).to eq "EVS"
        expect(bib.title.map(&:content).join(": ")).to include "Digital product passport"
        expect(bib.date.first.type).to eq "published"
        expect(bib.date.first.at.to_s).to eq "2026-06-15"
        expect(bib.relation.first.type).to eq "adoptedFrom"
        expect(bib.relation.first.bibitem.formattedref.content).to eq "EN 18216:2026"
        expect(bib.abstract.first.content).to include "data exchange protocols"
        expect(bib.ext.ics.first.code).to eq "35.240.63"
        expect(bib.ext.structuredidentifier.first.docnumber).to eq "18216"
        expect(bib.ext.structuredidentifier.first.agency).to eq ["EVS"]
        expect(bib.ext.flavor).to eq "evs"
        expect(bib.copyright.first.from).to eq "2026"
        expect(bib.place.first.city).to eq "Tallinn"
        expect(bib.fetched.to_s).to match(/\A\d{4}-\d{2}-\d{2}\z/)
      end
    end

    context "with a double adoption", vcr: { cassette_name: "evs_en_iso_14001_2026" } do
      it "splits the base documents into separate adoptedFrom relations" do
        bib = described_class.get "EVS-EN ISO 14001:2026"
        expect(bib.relation.map { |r| r.bibitem.formattedref.content })
          .to eq ["ISO 14001:2026", "EN ISO 14001:2026"]
      end
    end

    context "with a language code", vcr: { cassette_name: "evs_en_18216_2026_et" } do
      it "fetches the Estonian-language product" do
        bib = described_class.get "EVS-EN 18216:2026 et"
        expect(bib.language).to eq ["et"]
      end
    end

    context "with an unknown document", vcr: { cassette_name: "not_found" } do
      it "returns nil" do
        expect(described_class.get("EVS-EN 99999:2099")).to be_nil
      end
    end
  end

  describe ".search" do
    it "raises Relaton::RequestError on a transport failure" do
      stub_request(:any, %r{evs\.ee}).to_timeout
      expect { described_class.search("EVS-EN 18216:2026") }
        .to raise_error Relaton::RequestError
    end
  end
end
