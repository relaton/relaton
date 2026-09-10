RSpec.describe Relaton::Plateau::Bibliography do
  before do
    allow_any_instance_of(Relaton::Index::Type).to receive(:actual?).and_return(false)
    allow_any_instance_of(Relaton::Index::FileIO).to receive(:check_file).and_return(nil)
  end

  context "get" do
    it "handbook", vcr: "handbook" do
      file = "fixtures/handbook.xml"
      bib = described_class.get("PLATEAU Handbook #00 第1.0版")
      xml = bib.to_xml
      File.write file, xml, encoding: "UTF-8" unless File.exist? file
      expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
        .gsub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s)
    end

    it "technical-report", vcr: "technical_report" do
      file = "fixtures/technical_report.xml"
      bib = described_class.get("PLATEAU Technical Report #00")
      xml = bib.to_xml
      File.write file, xml, encoding: "UTF-8" unless File.exist? file
      expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
        .gsub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s)
    end

    # A well-formed id that is not in the index. This used to say
    # "PLATEAU Handbook #", which is not an identifier at all; a malformed
    # reference now raises (see the example below).
    it "not found" do
      expect { described_class.get("PLATEAU Handbook #99") }.to output(
        including("[relaton-plateau] WARN: (PLATEAU Handbook #99) Not found.")
      ).to_stderr_from_any_process
    end

    # The parse error passes through as itself, so relaton-cli can report it.
    it "raises for a malformed reference rather than reporting not found" do
      expect { described_class.get("PLATEAU Handbook #") }
        .to raise_error Pubid::Errors::ParseError
    end

    it "Handbook all editions", vcr: "handbook_all_editions" do
      bib = described_class.get("PLATEAU Handbook #00")
      expect(bib.docidentifier[0].content).to eq "PLATEAU Handbook #00"
      expect(bib.relation.size).to be > 1
      expect(bib.relation[0].type).to eq "hasEdition"
      expect(bib.relation[0].bibitem.docidentifier[0].content).to match(/PLATEAU Handbook #00 第[\d.]+版/)
    end

    it "Technical Report all editions", vcr: "technical_report_all_editions" do
      bib = described_class.get("PLATEAU Technical Report #00")
      expect(bib.docidentifier[0].content).to eq "PLATEAU Technical Report #00"
      expect(bib.relation.size).to eq 0
    end

    # A transport failure is a Relaton::RequestError, which Relaton::Db retries.
    it "raise error" do
      expect(described_class).to receive(:search).and_raise(SocketError)
      expect { described_class.get("PLATEAU Handbook #00 1.0") }.to raise_error Relaton::RequestError
    end

    # Anything else is not relabelled: it keeps its own class and backtrace.
    it "lets a non-transport error propagate as itself" do
      expect(described_class).to receive(:search).and_raise(NoMethodError)
      expect { described_class.get("PLATEAU Handbook #00 1.0") }.to raise_error NoMethodError
    end

    # "Accept both" — a legacy Latin reference resolves to the same canonical
    # record as the canonical query, via Pubid::Plateau's Latin-input parsing
    # (metanorma/pubid #269). The fetched document carries the canonical id.
    it "resolves a legacy Latin reference to the canonical record", vcr: "handbook" do
      bib = described_class.get("PLATEAU Handbook #00 1.0")
      expect(bib).not_to be_nil
      expect(bib.docidentifier.first.content).to eq "PLATEAU Handbook #00 第1.0版"
    end
  end
end
