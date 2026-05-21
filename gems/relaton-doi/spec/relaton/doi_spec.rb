# frozen_string_literal: true

RSpec.describe Relaton::Doi do
  before { Relaton::Doi.instance_variable_set :@configuration, nil }

  it "has a version number" do
    expect(Relaton::Doi::VERSION).not_to be nil
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
        expect(xml).to be_equivalent_to read_fixture(file)
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
      expect(xml).to be_equivalent_to read_fixture(file)
    end

    it "BIPM", vcr: "crossref_bipm" do
      file = "crossref_bipm.xml"
      resp = Relaton::Doi::Crossref.get "doi:10.1088/0026-1394/29/6/001"
      xml = resp.to_xml bibdata: true
      write_fixture file, xml
      expect(resp).to be_instance_of(Relaton::Bipm::ItemData)
      expect(xml).to be_equivalent_to read_fixture(file)
    end

    it "IEEE", vcr: "crossref_ieee" do
      file = "crossref_ieee.xml"
      resp = Relaton::Doi::Crossref.get "doi:10.1109/ieeestd.2014.6835311"
      xml = resp.to_xml bibdata: true
      write_fixture file, xml
      expect(resp).to be_instance_of(Relaton::Ieee::ItemData)
      expect(xml).to be_equivalent_to read_fixture(file)
    end

    shared_examples "fetch document" do |type, doi|
      it type, vcr: type do
        file = "#{type}.xml"
        resp = Relaton::Doi::Crossref.get "doi:#{doi}"
        xml = resp.to_xml bibdata: true
        write_fixture file, xml
        expect(xml).to be_equivalent_to read_fixture(file)
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
end
