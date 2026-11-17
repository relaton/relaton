# frozen_string_literal: true

RSpec.describe Relaton::Doi do
  before { Relaton::Doi.instance_variable_set :@configuration, nil }

  it "has a version number" do
    expect(Relaton::VERSION).not_to be nil
  end

  it "returs grammar hash" do
    expect(Relaton::Doi.grammar_hash.size).to eq 32
  end

  context "fetch document" do
    it "not found", vcr: "not_found" do
      expect do
        expect(Relaton::Doi::Crossref.get("doi:10.11111/RFC0000")).to be_nil
      end.to output(/\[relaton-doi\] INFO: \(doi:10.11111\/RFC0000\) Not found\./).to_stderr_from_any_process
    end

    it "NIST", vcr: "crossref_nist" do
      expect do
        file = "crossref_nist.xml"
        resp = Relaton::Doi::Crossref.get "doi:10.6028/nist.ir.8245"
        xml = resp.to_xml bibdata: true
        write_fixture file, xml
        expect(resp).to be_instance_of(Relaton::Nist::ItemData)
        expect(xml).to be_xml_equivalent_to read_fixture(file)
      end.to output(
        include(
          "[relaton-doi] INFO: (doi:10.6028/nist.ir.8245) Fetching from search.crossref.org ...",
          "[relaton-doi] INFO: (doi:10.6028/nist.ir.8245) Found: `10.6028/nist.ir.8245`",
        ),
      ).to_stderr_from_any_process
    end

    it "RFC", vcr: "crossref_rfc" do
      file = "crossref_rfc.xml"
      resp = Relaton::Doi::Crossref.get "doi:10.17487/RFC0001"
      xml = resp.to_xml bibdata: true
      write_fixture file, xml
      expect(resp).to be_instance_of(Relaton::Ietf::ItemData)
      expect(xml).to be_xml_equivalent_to read_fixture(file)
    end

    it "BIPM", vcr: "crossref_bipm" do
      file = "crossref_bipm.xml"
      resp = Relaton::Doi::Crossref.get "doi:10.1088/0026-1394/29/6/001"
      xml = resp.to_xml bibdata: true
      write_fixture file, xml
      expect(resp).to be_instance_of(Relaton::Bipm::ItemData)
      expect(xml).to be_xml_equivalent_to read_fixture(file)
    end

    it "IEEE", vcr: "crossref_ieee" do
      file = "crossref_ieee.xml"
      resp = Relaton::Doi::Crossref.get "doi:10.1109/ieeestd.2014.6835311"
      xml = resp.to_xml bibdata: true
      write_fixture file, xml
      expect(resp).to be_instance_of(Relaton::Ieee::ItemData)
      expect(xml).to be_xml_equivalent_to read_fixture(file)
    end

    shared_examples "fetch document" do |type, doi|
      it type, vcr: type do
        file = "#{type}.xml"
        resp = Relaton::Doi::Crossref.get "doi:#{doi}"
        xml = resp.to_xml bibdata: true
        write_fixture file, xml
        expect(xml).to be_xml_equivalent_to read_fixture(file)
        # Downstream renderers reject a bibitem that Nokogiri cannot parse.
        # See metanorma-pdfa#99.
        expect(Nokogiri::XML(xml).errors).to be_empty
      end
    end

    context "fetch editors" do
      it_behaves_like "fetch document", "book_chapter_editors", "10.1037/0000120-016"
      it_behaves_like "fetch document", "book_editors", "10.1007/978-1-4471-1578-6"
    end

    it_behaves_like "fetch document", "book-chapter", "10.1515/9783110889406.257"
    it_behaves_like "fetch document", "book-part", "10.1215/9781478007609-047"
    it_behaves_like "fetch document", "book-section", "10.14509/23007"
    it_behaves_like "fetch document", "book-series", "10.1787/20743300"
    it_behaves_like "fetch document", "book-set", "10.7139/2017.978-1-56900-592-7"
    it_behaves_like "fetch document", "book-track", "10.1017/isbn-9780511132971.eh132-135"
    it_behaves_like "fetch document", "book", "10.1093/acprof:oso/9780199681624.001.0001"
    it_behaves_like "fetch document", "component", "10.1371/journal.pone.0020476.s005"
    it_behaves_like "fetch document", "database", "10.6019/pxd038478"
    it_behaves_like "fetch document", "dataset", "10.1163/2214-871x_ei1_sim_5628"
    it_behaves_like "fetch document", "dissertation", "10.11606/t.8.2017.tde-08052017-100442"
    it_behaves_like "fetch document", "edited-book", "10.1515/9780691229409"
    it_behaves_like "fetch document", "grant", "10.46936/cpcy.proj.2019.50733/60006578"
    it_behaves_like "fetch document", "journal-article", "10.1515/text.2001.011"
    it_behaves_like "fetch document", "journal-article-jats-abstract",
                    "10.1145/964965.808606"
    it_behaves_like "fetch document", "journal-issue-1", "10.1515/cog.2007.005"
    it_behaves_like "fetch document", "journal-issue-2", "10.1111/read.1991.25.issue-1"
    it_behaves_like "fetch document", "journal-volume", "10.46409/001.rlpt5688"
    it_behaves_like "fetch document", "journal", "10.46528/jk"
    it_behaves_like "fetch document", "monograph-1", "10.1515/9783110889406"
    it_behaves_like "fetch document", "monograph-2", "10.5962/bhl.title.124254"
    it_behaves_like "fetch document", "other", "10.1108/oxan-es268033"
    it_behaves_like "fetch document", "peer-review", "10.1111/jan.15115/v3/decision1"
    it_behaves_like "fetch document", "posted-content", "10.1101/751156"
    it_behaves_like "fetch document", "proceedings-article", "10.1109/icpadm.1994.414074"
    it_behaves_like "fetch document", "proceedings-article-encoded-title", "10.1117/12.410780"
    it_behaves_like "fetch document", "proceedings-series", "10.15405/epsbs(2357-1330).2021.6.1"
    it_behaves_like "fetch document", "proceedings", "10.1145/1947940"
    it_behaves_like "fetch document", "reference-book", "10.1201/9781439864852"
    it_behaves_like "fetch document", "reference-entry", "10.1093/ww/9780199540884.013.u52741"
    it_behaves_like "fetch document", "report-component", "10.3133/ofr72419"
    it_behaves_like "fetch document", "report-series", "10.1787/5jxvk6shpvs4-en"
    it_behaves_like "fetch document", "report", "10.3133/i747"
    it_behaves_like "fetch document", "standard", "10.31030/2640440"
  end

  # relaton#577, relaton-doi#20: doi.org names the registration agency, and
  # the DOI goes to that agency's API.
  describe ".get" do
    it "asks Crossref for a Crossref DOI" do
      expect(Relaton::Doi::RegistrationAgency).to receive(:lookup)
        .with("10.1109/5.771073").and_return("Crossref")
      expect(Relaton::Doi::Crossref).to receive(:get).with("doi:10.1109/5.771073")
        .and_return(:item)
      expect(described_class.get("doi:10.1109/5.771073")).to be :item
    end

    it "asks DataCite for a DataCite DOI" do
      expect(Relaton::Doi::RegistrationAgency).to receive(:lookup)
        .with("10.13140/RG.2.1.4576.8809").and_return("DataCite")
      expect(Relaton::Doi::Datacite).to receive(:get)
        .with("doi:10.13140/RG.2.1.4576.8809").and_return(:item)
      expect(described_class.get("doi:10.13140/RG.2.1.4576.8809")).to be :item
    end

    it "accepts a parsed pubid" do
      require "pubid"
      pubid = Pubid::Doi::Identifier.parse "doi:10.13140/RG.2.1.4576.8809"
      expect(Relaton::Doi::RegistrationAgency).to receive(:lookup)
        .with("10.13140/RG.2.1.4576.8809").and_return("DataCite")
      expect(Relaton::Doi::Datacite).to receive(:get).with(pubid).and_return(:item)
      expect(described_class.get(pubid)).to be :item
    end

    it "answers nil when DataCite has no record of a DataCite DOI" do
      expect(Relaton::Doi::RegistrationAgency).to receive(:lookup).and_return("DataCite")
      expect(Relaton::Doi::Http).to receive(:get_json)
        .with("https://api.datacite.org/dois/10.5281%2Fzenodo.0", "DataCite").and_return(nil)
      expect do
        expect(described_class.get("doi:10.5281/zenodo.0")).to be_nil
      end.to output(/Not found\./).to_stderr_from_any_process
    end

    it "answers nil, with a log line, for a DOI that does not exist" do
      expect(Relaton::Doi::RegistrationAgency).to receive(:lookup).and_return(nil)
      expect(Relaton::Doi::Crossref).not_to receive(:get)
      expect do
        expect(described_class.get("doi:10.1000/nope")).to be_nil
      end.to output(/\(doi:10.1000\/nope\) Not found: doi.org has no registration agency/)
        .to_stderr_from_any_process
    end

    it "answers nil, with a log line, for an agency relaton does not read" do
      expect(Relaton::Doi::RegistrationAgency).to receive(:lookup).and_return("mEDRA")
      expect do
        expect(described_class.get("doi:10.1400/123")).to be_nil
      end.to output(/registration agency mEDRA is not supported/)
        .to_stderr_from_any_process
    end

    it "fetches the DOI of relaton-doi#20 from DataCite", vcr: "datacite_rg" do
      file = "datacite_rg.xml"
      resp = described_class.get "doi:10.13140/RG.2.1.4576.8809"
      xml = resp.to_xml bibdata: true
      write_fixture file, xml
      expect(resp).to be_instance_of(Relaton::Bib::ItemData)
      expect(xml).to be_xml_equivalent_to read_fixture(file)
      expect(Nokogiri::XML(xml).errors).to be_empty
    end

    it "fetches a Zenodo DOI from DataCite", vcr: "datacite_zenodo" do
      file = "datacite_zenodo.xml"
      resp = described_class.get "doi:10.5281/zenodo.3242074"
      xml = resp.to_xml bibdata: true
      write_fixture file, xml
      expect(xml).to be_xml_equivalent_to read_fixture(file)
    end

    it "fetches a Crossref DOI from Crossref", vcr: "registration_agency_crossref" do
      resp = described_class.get "doi:10.1109/ieeestd.2014.6835311"
      expect(resp).to be_instance_of(Relaton::Ieee::ItemData)
      expect(resp.docidentifier.first.content).to eq "10.1109/ieeestd.2014.6835311"
    end
  end
end
