# frozen_string_literal: true

require "relaton/nist/data_fetcher"

RSpec.describe Relaton::Nist::DataFetcher do
  context "create instance and call fetch" do
    let(:df) { double "fetcher" }
    before { expect(df).to receive(:fetch).with(nil) }

    it "default output & format" do
      expect(described_class).to receive(:new).with("data", "yaml").and_return df
      described_class.fetch
    end

    it "specified output & format" do
      expect(described_class).to receive(:new).with("dir", "xml").and_return df
      described_class.fetch output: "dir", format: "xml"
    end
  end

  context "instance methods" do
    subject { described_class.new "data", "yaml" }
    let(:xml) { File.read "fixtures/allrecords-MODS.xml", encoding: "UTF-8" }

    it "#index" do
      expect(subject.index).to be_instance_of Relaton::Index::Type
    end

    context "#fetch" do
      it "success" do
        expect(subject.index).to receive(:save)
        expect(subject).to receive(:fetch_tech_pubs)
        # expect(subject).to receive(:add_static_files)
        subject.fetch
      end
    end

    it "#fetch_tech_pubs" do
      page = double("page", body: xml)
      agent = double("agent")
      expect(Mechanize).to receive(:new).and_return agent
      expect(agent).to receive(:get).with(subject.source_url).and_return page
      parser = double "parser"
      expect(parser).to receive(:parse).and_return(:bib).twice
      expect(Relaton::Nist::ModsParser).to receive(:new)
        .with(kind_of(LocMods::Record), kind_of(Hash), kind_of(Hash)).and_return(parser).twice
      expect(subject).to receive(:write_file).with(:bib).twice
      subject.fetch_tech_pubs
    end

    context "#source_url" do
      let(:base) { "https://github.com/usnistgov/NIST-Tech-Pubs/releases" }

      it "resolves the latest release when no source is given" do
        expect(subject.source_url).to eq "#{base}/latest/download/allrecords-MODS.xml"
      end

      it "resolves the latest release for an explicit \"latest\" (any case)" do
        expect(subject.source_url("latest")).to eq "#{base}/latest/download/allrecords-MODS.xml"
        expect(subject.source_url("LATEST")).to eq "#{base}/latest/download/allrecords-MODS.xml"
      end

      it "resolves the latest release for a blank source" do
        expect(subject.source_url("  ")).to eq "#{base}/latest/download/allrecords-MODS.xml"
      end

      it "pins a specific release tag" do
        expect(subject.source_url("June2026")).to eq "#{base}/download/June2026/allrecords-MODS.xml"
      end
    end

    context "#write_file" do
      let(:docid) { Relaton::Nist::Docidentifier.new(type: "NIST", content: "NIST IR 8296-12") }
      let(:bib) { Relaton::Bib::ItemData.new(docidentifier: [docid]) }

      let(:pid) { double "pubid" }

      before do
        allow(subject).to receive(:pubid).with("NIST IR 8296-12").and_return(pid)
        expect(subject.index).to receive(:add_or_update).with(pid, "data/nistir-8296-12.yaml")
        expect(File).to receive(:write).with("data/nistir-8296-12.yaml", :content, encoding: "UTF-8")
        expect(subject).to receive(:serialize).with(bib).and_return :content
      end

      it "success" do
        expect { subject.write_file bib }.not_to output.to_stderr_from_any_process
      end

      it "file exists" do
        subject.instance_variable_get(:@files) << "data/nistir-8296-12.yaml"
        expect { subject.write_file bib }.to output(
          /File data\/nistir-8296-12\.yaml exists\. Docid: NIST IR 8296-12/,
        ).to_stderr_from_any_process
      end
    end

    context "#write_file with no identifier" do
      let(:title) { Relaton::Bib::Title.new(content: "Quick start guide", type: "main") }
      let(:bib) { Relaton::Bib::ItemData.new(docidentifier: [], title: [title]) }

      it "does not crash, skips the file, and records the failure" do
        expect(File).not_to receive(:write)
        expect(subject.index).not_to receive(:add_or_update)
        expect { subject.write_file bib }.not_to raise_error
        expect(subject.failures).to include(/no identifier.*Quick start guide/)
      end

      it "falls back to a label when the record has no usable title (nil/blank content)" do
        blank = Relaton::Bib::Title.new(type: "main")
        titleless = Relaton::Bib::ItemData.new(docidentifier: [], title: [blank])
        expect { subject.write_file titleless }.not_to raise_error
        expect(subject.failures).to include(/no identifier.*unknown title/)
      end
    end

    context "#write_file with an unparseable identifier" do
      let(:docid) { Relaton::Nist::Docidentifier.new(type: "NIST", content: "NIST RB 6") }
      let(:bib) { Relaton::Bib::ItemData.new(docidentifier: [docid]) }

      before do
        allow(subject).to receive(:pubid).with("NIST RB 6").and_return(nil)
        allow(subject).to receive(:serialize).with(bib).and_return :content
      end

      it "still writes the file but records the id as not indexed" do
        expect(subject.index).not_to receive(:add_or_update)
        expect(File).to receive(:write).with("data/nist-rb-6.yaml", :content, encoding: "UTF-8")
        subject.write_file bib
        expect(subject.failures).to include(/Unparseable id `NIST RB 6` was not indexed/)
      end
    end

    context "#pubid" do
      it "parses a valid docidentifier into a Pubid::Nist::Identifier" do
        pid = subject.pubid "NIST IR 8200"
        expect(pid).to be_a ::Pubid::Nist::Identifier
        expect(pid.to_s).to eq "NIST IR 8200"
      end

      it "returns nil for an unparseable id (single bad id never aborts the crawl)" do
        expect(subject.pubid("!!! totally bogus @@@")).to be_nil
      end
    end

    context "#report_errors" do
      it "surfaces each accumulated failure at error level, then calls super" do
        subject.failures << "boom one" << "boom two"
        allow(subject).to receive(:gh_issue)
        expect(subject).to receive(:log_error).with("boom one")
        expect(subject).to receive(:log_error).with("boom two")
        # the Core::DataFetcher#report_errors path (super) reports @errors and
        # creates the issue; stub its side effects to keep the unit focused.
        allow(subject).to receive(:gh_issue_channel).and_return([nil, "title"])
        subject.report_errors
      end
    end

    context "#serialize" do
      let(:bib) { double "BibItem" }

      it "yaml" do
        expect(Relaton::Nist::Item).to receive(:to_yaml).with(bib).and_return :yaml
        expect(subject.serialize(bib)).to eq :yaml
      end

      it "xml" do
        subject.instance_variable_set :@format, "xml"
        expect(Relaton::Nist::Bibdata).to receive(:to_xml).with(bib).and_return :xml
        expect(subject.serialize(bib)).to eq :xml
      end

      it "bibxml" do
        subject.instance_variable_set :@format, "bibxml"
        expect(bib).to receive(:to_rfcxml).with(no_args).and_return :bibxml
        expect(subject.serialize(bib)).to eq :bibxml
      end
    end
  end
end
