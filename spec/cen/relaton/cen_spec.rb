# frozen_string_literal: true

RSpec.describe Relaton::Cen do
  it "has a version number" do
    expect(Relaton::Cen::VERSION).not_to be nil
  end

  it "retunrs grammar hash" do
    hash = Relaton::Cen.grammar_hash
    expect(hash).to be_instance_of String
    expect(hash.size).to eq 32
  end

  it "gets code" do
    VCR.use_cassette "cen_iso_ts_21003_7" do
      file = "fixtures/bibdata.xml"
      bib = Relaton::Cen::Bibliography.get "CEN ISO/TS 21003-7"
      xml = bib.to_xml bibdata: true
      write_file file, xml
      expect(xml).to be_equivalent_to read_xml(file)
      schema = Jing.new "../../grammar/relaton-cen-compile.rng"
      errors = schema.validate file
      expect(errors).to eq []
    end
  end

  it "get document with subcommittee" do
    VCR.use_cassette "subcommittee" do
      bib = Relaton::Cen::Bibliography.get "EN 10160:1999"
      expect(bib.contributor[0].organization.subdivision[1].name[0].content).to eq(
        "Test methods for steel (other than chemical analysis)",
      )
    end
  end

  it "get EN", vcr: "en_13306" do
    expect do
      bib = Relaton::Cen::Bibliography.get "EN 13306"
      expect(bib.docidentifier[0].content).to eq "EN 13306"
    end.to output(/Found: `EN 13306`/).to_stderr_from_any_process
  end

  it "get ENV", vcr: "env_1993_1_1" do
    bib = Relaton::Cen::Bibliography.get "ENV 1613:1995"
    expect(bib.docidentifier[0].content).to eq "ENV 1613:1995"
  end

  it "get CWA", vcr: "cwa_14050_21_2000" do
    bib = Relaton::Cen::Bibliography.get "CWA 14050-21:2000"
    expect(bib.docidentifier[0].content).to eq "CWA 14050-21:2000"
  end

  it "get HD", vcr: "hd_1215_2_1988" do
    bib = Relaton::Cen::Bibliography.get "HD 1215-2:1988"
    expect(bib.docidentifier[0].content).to eq "HD 1215-2:1988"
  end

  it "get CR", vcr: "cr_12101_5_2000" do
    bib = Relaton::Cen::Bibliography.get "CR 12101-5:2000"
    expect(bib.docidentifier[0].content).to eq "CR 12101-5:2000"
  end

  it "keeep year", vcr: "en_13306" do
    expect do
      bib = Relaton::Cen::Bibliography.get "EN 13306", nil, keep_year: true
      expect(bib.docidentifier[0].content).to eq "EN 13306:2017"
    end.to output(/Found: `EN 13306:2017`/).to_stderr_from_any_process
  end

  it "get amendment" do
    VCR.use_cassette "en_285_2015_a1_2021" do
      bib = Relaton::Cen::Bibliography.get "EN 285:2015+A1"
      expect(bib.docidentifier[0].content).to eq "EN 285:2015+A1:2021"
    end
  end

  it "get lates without part & year" do
    VCR.use_cassette "en_1325" do
      bib = Relaton::Cen::Bibliography.get "EN 1325"
      expect(bib.docidentifier[0].content).to eq "EN 1325"
    end
  end

  context "get document by year" do
    it "in code" do
      VCR.use_cassette "cen_iso_ts_21003_7" do
        bib = Relaton::Cen::Bibliography.get "CEN ISO/TS 21003-7:2019"
        expect(bib.docidentifier[0].content).to eq "CEN ISO/TS 21003-7:2019"
      end
    end

    it "in option", vcr: "cen_iso_ts_21003_7" do
      expect do
        bib = Relaton::Cen::Bibliography.get "CEN ISO/TS 21003-7", "2019"
        expect(bib.docidentifier[0].content).to eq "CEN ISO/TS 21003-7:2019"
      end.to output(/\(CEN ISO\/TS 21003-7:2019\) Found: `CEN ISO\/TS 21003-7:2019`/).to_stderr_from_any_process
    end

    it "return nil when year is incorrect" do
      VCR.use_cassette "cen_iso_ts_21003_7" do
        bib = ""
        expect do
          bib = Relaton::Cen::Bibliography.get "CEN ISO/TS 21003-7", "2018"
        end.to output(/There was no match for `2018`/).to_stderr_from_any_process
        expect(bib).to be_nil
      end
    end
  end

  it "raise RequestError" do
    agent = double "Mechanize agent"
    expect(agent).to receive(:user_agent_alias=)
    page = double "Mechanize response", code: 500
    expect(agent).to receive(:get).and_raise Mechanize::ResponseCodeError.new(page)
    expect(Mechanize).to receive(:new).and_return agent
    expect do
      Relaton::Cen::Bibliography.get "CEN ISO/TS 21003-7"
    end.to raise_error Relaton::RequestError
  end

  it "returns nil when document doesn't exist" do
    VCR.use_cassette "not_found" do
      bib = ""
      expect do
        bib = Relaton::Cen::Bibliography.get "CEN NOT FOUND"
      end.to output(/\[relaton-cen\] INFO: \(CEN NOT FOUND\) Not found\./).to_stderr_from_any_process
      expect(bib).to be_nil
    end
  end

  it "returns nil when referense is empty" do
    bib = Relaton::Cen::Bibliography.get ""
    expect(bib).to be_nil
  end
end
