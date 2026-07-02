RSpec.describe Relaton::Plateau::Bibliography do
  before do
    allow_any_instance_of(Relaton::Index::Type).to receive(:actual?).and_return(false)
    allow_any_instance_of(Relaton::Index::FileIO).to receive(:check_file).and_return(nil)
  end

  context "get" do
    it "handbook", vcr: "handbook" do
      file = "fixtures/handbook.xml"
      bib = described_class.get("PLATEAU Handbook #00 1.0")
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

    it "not found" do
      expect { described_class.get("PLATEAU Handbook #") }.to output(
        including("[relaton-plateau] WARN: (PLATEAU Handbook #) Not found.")
      ).to_stderr_from_any_process
    end

    it "Handbook all editions", vcr: "handbook_all_editions" do
      bib = described_class.get("PLATEAU Handbook #00")
      expect(bib.docidentifier[0].content).to eq "PLATEAU Handbook #00"
      expect(bib.relation.size).to be > 1
      expect(bib.relation[0].type).to eq "hasEdition"
      expect(bib.relation[0].bibitem.docidentifier[0].content).to match(/PLATEAU Handbook #00 \d+\.\d+/)
    end

    it "Technical Report all editions", vcr: "technical_report_all_editions" do
      bib = described_class.get("PLATEAU Technical Report #00")
      expect(bib.docidentifier[0].content).to eq "PLATEAU Technical Report #00 1.0"
      expect(bib.relation.size).to eq 0
    end

    it "raise error" do
      expect(described_class).to receive(:search).and_raise(StandardError)
      expect { described_class.get("PLATEAU Handbook #00 1.0") }.to raise_error Relaton::Plateau::Error
    end
  end
end
