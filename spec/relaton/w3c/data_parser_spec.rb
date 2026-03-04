# frozen_string_literal: true

require_relative "../../../lib/relaton/w3c/data_fetcher"

RSpec.describe Relaton::W3c::DataParser do
  let(:client) { W3cApi::Client.new }
  let(:doc) { subject.parse }

  subject { described_class.new specification }

  before { Relaton::W3c::RateLimitHandler.fetched_objects.clear }

  it "create instance and run parsing" do
    parser = double "parser"
    expect(parser).to receive(:parse)
    expect(described_class).to receive(:new).with(:spec).and_return(parser)
    described_class.parse :spec
  end

  it "initialize parser" do
    subj = described_class.new :spec
    expect(subj.instance_variable_get(:@spec)).to eq :spec
  end

  context "instance versioned", vcr: "webrtc-20241008" do
    let(:specification) { client.specification_version("webrtc", "20241008") }

    it "parse doc" do
      expect(doc).to be_instance_of Relaton::W3c::ItemData
      expect(doc.type).to eq "standard"
      expect(doc.ext.doctype.content).to eq "technicalReport"
      expect(doc.language).to eq ["en"]
      expect(doc.script).to eq ["Latn"]
      expect(doc.status.stage.content).to eq "Recommendation"
      expect(doc.title[0].content).to eq "WebRTC: Real-Time Communication in Browsers"
      expect(doc.source[0].content.to_s).to eq "https://www.w3.org/TR/2024/REC-webrtc-20241008/"
      expect(doc.source[0].type).to eq "src"
      expect(doc.docidentifier[0].content).to eq "W3C REC-webrtc-20241008"
      expect(doc.docidentifier[0].type).to eq "W3C"
      expect(doc.docidentifier[0].primary).to be true
      expect(doc.docnumber).to eq "REC-webrtc-20241008"
      expect(doc.series[0].title[0].content).to eq "W3C Recommendation"
      expect(doc.series[0].number).to eq "REC-webrtc-20241008"
      expect(doc.date[0].type).to eq "published"
      expect(doc.date[0].at.to_s).to eq "2024-10-08"
      expect(doc.relation[0].type).to eq "editionOf"
      expect(doc.relation[0].bibitem.title[0].content).to eq "WebRTC: Real-Time Communication in Browsers"
      expect(doc.relation[0].bibitem.docidentifier[0].content).to eq "W3C webrtc"
      expect(doc.relation[0].bibitem.docidentifier[0].type).to eq "W3C"
      expect(doc.relation[0].bibitem.source[0].content.to_s).to eq "https://www.w3.org/TR/webrtc/"
      expect(doc.relation[0].bibitem.source[0].type).to eq "src"
      expect(doc.relation[1].type).to eq "obsoletes"
      expect(doc.relation[1].bibitem.docidentifier[0].content).to eq "W3C REC-webrtc-20230306"
      expect(doc.relation[2].type).to eq "updatedBy"
      expect(doc.relation[2].description.content).to eq "errata"
      expect(doc.relation[2].bibitem.docidentifier[0].content).to eq "W3C REC-webrtc-20250313"
      expect(doc.contributor[0].organization).to be_instance_of Relaton::Bib::Organization
      expect(doc.contributor[0].organization.name[0].content).to eq "World Wide Web Consortium"
      expect(doc.contributor[0].organization.abbreviation.content).to eq "W3C"
      expect(doc.contributor[0].organization.uri.content.to_s).to eq "https://www.w3.org"
      expect(doc.contributor[0].role[0].type).to eq "publisher"
      expect(doc.contributor[1].person.name.surname.content).to eq "Jennings"
      expect(doc.contributor[1].person.name.forename[0].content).to eq "Cullen"
      expect(doc.contributor[1].person.name.forename[0].language).to eq "en"
      expect(doc.contributor[1].person.name.forename[0].script).to eq "Latn"
      expect(doc.contributor[1].role[0].type).to eq "editor"
    end
  end

  context "instance unversioned", vcr: "webrtc" do
    let(:specification) { client.specification("webrtc") }

    it "parse doc" do
      expect(doc.ext.doctype.content).to eq "technicalReport"
      expect(doc.status).to be_nil
      expect(doc.title[0].content).to eq "WebRTC: Real-Time Communication in Browsers"
      expect(doc.source[0].content.to_s).to eq "https://www.w3.org/TR/webrtc/"
      expect(doc.docidentifier[0].content).to eq "W3C webrtc"
      expect(doc.docnumber).to eq "webrtc"
      expect(doc.series[0].title[0].content).to eq "W3C technicalReport"
      expect(doc.series[0].number).to eq "webrtc"
      expect(doc.date).to be_empty
      expect(doc.relation.size).to eq 38
      expect(doc.relation[0].type).to eq "hasEdition"
      expect(doc.relation[0].bibitem.docidentifier[0].content).to eq "W3C REC-webrtc-20250313"
      expect(doc.contributor.size).to eq 1
    end
  end
end
