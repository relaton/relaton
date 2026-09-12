require "relaton/ieee/data_fetcher"

RSpec.describe Relaton::Ieee::DataFetcher do
  it "fetch data" do
    expect(FileUtils).to receive(:mkdir_p).with("data")
    files = Dir["fixtures/rawbib/**/*.{xml,zip}"]
    expect(Dir).to receive(:[]).with("ieee-rawbib/**/*.{xml,zip}").and_return files
    expect(File).to receive(:write).with("data/ieee-p802-22-d3-0-march-2011.yaml", kind_of(String), encoding: "UTF-8")
    described_class.fetch
  end

  context "instance" do
    let(:df) { described_class.new "data", "yaml" }

    it "warn if error" do
      allow(File).to receive(:read).and_raise(StandardError, "boom")
      expect do
        df.send(:parse_entry, 0, "fixtures/rawbib/file.xml")
      end.to output(/File: fixtures\/rawbib\/file\.xml/).to_stderr_from_any_process
    end

    it "handle empty file" do
      allow(File).to receive(:read).with("file.xml", encoding: "UTF-8").and_return ""
      expect do
        expect(df.send(:parse_entry, 0, "file.xml")).to be_nil
      end.to output(/WARN: Empty file: `file\.xml`/).to_stderr_from_any_process
    end

    it "create relation" do
      rel = df.create_relation "V", "AIEE 15.1928-05"
      expect(rel).to be_a Relaton::Bib::Relation
      expect(rel.type).to eq "updates"
      expect(rel.description.content).to eq "revises"
      expect(rel.bibitem).to be_instance_of Relaton::Ieee::ItemData
      expect(rel.bibitem.docidentifier[0].content).to eq "AIEE 15.1928-05"
      expect(rel.bibitem.docidentifier[0].type).to eq "IEEE"
      expect(rel.bibitem.docidentifier[0].primary).to be true
      expect(rel.bibitem.formattedref.content).to eq "AIEE 15.1928-05"
    end

    context "when ouput file exists" do
      let(:bib) do
        docid = Relaton::Bib::Docidentifier.new content: "IEEE 5678", primary: true
        title = Relaton::Bib::Title.new(content: "Title")
        Relaton::Ieee::ItemData.new docnumber: "5678", title: [title], docidentifier: [docid]
      end

      before(:each) do
        df.backrefs["4321"] = "IEEE 5678"
      end

      it "warn" do
        xml = <<~XML
          <publication>
            <title>Title</title>
            <publicationinfo>
              <amsid>1234</amsid>
              <standard_id>4321</standard_id>
              <stdnumber>5677</stdnumber>
            </publicationinfo>
          </publication>
        XML
        doc = ::Ieee::Idams::Publication.from_xml(xml)
        bib.instance_variable_set :@docnumber, "3412"
        expect { df.send(:commit_doc, doc, bib, "file.xml") }.to output(
          /WARN: Document exists ID: `IEEE 5678` AMSID: `1234` source: `file\.xml`\. Other AMSID: `4321`/,
        ).to_stderr_from_any_process
      end

      it "rewrite file if PubID includes a docnumber" do
        xml = <<~XML
          <publication>
            <title>IEEE 5678 Title</title>
            <publicationinfo>
              <amsid>1234</amsid>
              <standard_id>4321</standard_id>
              <stdnumber>5678</stdnumber>
            </publicationinfo>
          </publication>
        XML
        doc = ::Ieee::Idams::Publication.from_xml(xml)
        expect(File).to receive(:write).with("data/5678.yaml", kind_of(String), encoding: "UTF-8")
        expect { df.send(:commit_doc, doc, bib, "file.xml") }.to output(
          /WARN: Document exists ID: `IEEE 5678` AMSID: `1234` source: `file\.xml`\. Other AMSID: `4321`/,
        ).to_stderr_from_any_process
      end
    end

    context "hamdle relations" do
      before(:each) do
        df.send(:crossrefs)["5678"] = [{ amsid: "3412", type: "V" }]
      end

      it "add cross-reference to existed PubID" do
        amsid = double "amsid", date_string: "1234", type: "C"
        df.add_crossref "5678", amsid
        expect(df.instance_variable_get(:@crossrefs)["5678"]).to eq [
          { amsid: "3412", type: "V" }, { amsid: "1234", type: "C" }
        ]
      end

      it "udate unresolved relations" do
        df.backrefs["3412"] = "7809"
        docid = Relaton::Bib::Docidentifier.new content: "5678"
        title = Relaton::Bib::Title.new(content: "Title")
        bib = Relaton::Ieee::ItemData.new title: [title], docidentifier: [docid]
        expect(df).to receive(:read_bib).with("5678").and_return bib
        expect(df).to receive(:save_doc) do |arg|
          expect(arg.relation[0].type).to eq "updates"
          expect(arg.relation[0].description.content).to eq "revises"
          expect(arg.relation[0].bibitem.formattedref.content).to eq "7809"
        end
        df.send :update_relations
      end
    end

    context "read saved document" do
      before(:each) { allow(File).to receive(:read).and_call_original }

      it "in YAML format" do
        yaml = {
          "title" => {
            "content" => "Title",
            "type" => "main",
            "language" => "en",
            "script" => "Latn",
            "format" => "text/plain",
          },
          "docid" => { "id" => "5678", "type" => "IEEE" },
        }.to_yaml
        expect(File).to receive(:read).with("data/5678.yaml", encoding: "UTF-8").and_return yaml
        expect(df.send(:read_bib, "5678")).to be_instance_of Relaton::Ieee::ItemData
      end

      it "in XML format" do
        xml = <<~XML
          <bibitem>
            <title type="main" format="text/plain" language="en" script="Latn">Title</title>
            <docidentifier type="IEEE">5678</docidentifier>
          </bibitem>
        XML
        df.instance_variable_set :@format, "xml"
        df.instance_variable_set :@ext, "xml"
        expect(File).to receive(:read).with("data/5678.xml", encoding: "UTF-8").and_return xml
        expect(df.send(:read_bib, "5678")).to be_instance_of Relaton::Ieee::ItemData
      end

      it "in BibXML format" do
        xml = <<~XML
          <reference anchor="IEEEStdP802.11ma/D3.0">
            <front>
              <title>Title</title>
              <date year="2021" month="January"/>
            </front>
          </reference>
        XML
        df.instance_variable_set :@format, "bibxml"
        df.instance_variable_set :@ext, "xml"
        expect(File).to receive(:read).with("data/5678.xml", encoding: "UTF-8").and_return xml
        expect(df.send(:read_bib, "5678")).to be_instance_of Relaton::Ieee::ItemData
      end
    end

    it "return nil and warn if docnumber is nil" do
      xml = <<~XML
        <publication>
          <normtitle><![CDATA[Title]]></normtitle>
        </publication>
      XML
      allow(File).to receive(:read).with("filename.xml", encoding: "UTF-8").and_return xml
      bib = double "bib", docnumber: nil
      dp = double "dp", parse: bib
      expect(Relaton::Ieee::IdamsParser).to receive(:new).with(kind_of(::Ieee::Idams::PubModel), df, kind_of(Hash)).and_return dp
      expect do
        expect(df.send(:parse_entry, 0, "filename.xml")).to be_nil
      end.to output(
        "[relaton-ieee] WARN: PubID parse error. Normtitle: `Title`, file: `filename.xml`\n"
      ).to_stderr_from_any_process
    end

    # A white paper or a research document has no standard number: IEEE gives
    # it no designation and cites it by title. Its `stdnumber` is a category,
    # and its `normtitle` is a title, so any id made from them is a fragment
    # (`IEEE Std 802` from "IEEE 802 Nendica Report: ..."), and records that
    # share a fragment overwrite each other. Skip such a record.
    context "record with no standard number" do
      let(:xml) do
        <<~XML
          <publication>
            <normtitle><![CDATA[IEEE 802 Nendica Report: The Lossless Network for Data Centers]]></normtitle>
            <publicationinfo>
              <stdnumber>White Paper</stdnumber>
              <publicationsubtype>Whitepapers</publicationsubtype>
              <standard_id>10082</standard_id>
            </publicationinfo>
          </publication>
        XML
      end

      it "skips it in the full parse" do
        allow(File).to receive(:read).with("wp.xml", encoding: "UTF-8").and_return xml
        expect(Relaton::Ieee::IdamsParser).not_to receive(:new)
        expect do
          expect(df.send(:parse_entry, 0, "wp.xml")).to be_nil
        end.to output(/WARN: No standard number/).to_stderr_from_any_process
      end

      it "skips it in the prefilter" do
        allow(File).to receive(:read).with("wp.xml", encoding: "UTF-8").and_return xml
        expect(df.send(:extract_index_entry, 0, "wp.xml")).to be_nil
      end

      it "keeps a record of that type that has a number" do
        std = xml.sub("White Paper", "ST 430-9:2008 Am1:2011")
                 .sub("IEEE 802 Nendica Report: The Lossless Network for Data Centers",
                      "Amendment 1:2011 to SMPTE ST 430-9:2008")
        allow(File).to receive(:read).with("smpte.xml", encoding: "UTF-8").and_return std
        entry = df.send(:extract_index_entry, 0, "smpte.xml")
        expect(entry[2]).to eq "IEEE ST 430-9:2008 Am1:2011"
      end

      it "keeps a standard document with a category stdnumber" do
        std = xml.sub("Whitepapers", "Standard Docs")
        allow(File).to receive(:read).with("std.xml", encoding: "UTF-8").and_return std
        expect(df.send(:extract_index_entry, 0, "std.xml")[2]).to eq "IEEE Std 802"
      end
    end

    context "save document" do
      let(:bib) { Relaton::Ieee::ItemData.new docnumber: "5678" }

      it "in XML format" do
        df.instance_variable_set :@format, "xml"
        df.instance_variable_set :@ext, "xml"
        expect(File).to receive(:write).with("data/5678.xml", /<bibdata/, encoding: "UTF-8")
        df.send :save_doc, bib
      end

      it "in YAML format" do
        expect(File).to receive(:write).with("data/5678.yaml", /docnumber: '5678'/, encoding: "UTF-8")
        df.send :save_doc, bib
      end

      it "in BibXML format" do
        df.instance_variable_set :@format, "bibxml"
        df.instance_variable_set :@ext, "xml"
        expect(File).to receive(:write).with("data/5678.xml", /anchor="5678"/, encoding: "UTF-8")
        df.send :save_doc, bib
      end
    end

    context "commit resilience" do
      it "rescues and logs a raising commit_doc instead of propagating" do
        allow(df).to receive(:parse_entry).with(0, "bad.xml").and_return [0, "bad.xml", :doc, :bib, {}]
        allow(df).to receive(:commit_doc).and_raise(Errno::ENAMETOOLONG)
        expect do
          df.send(:commit_entry, 0, "bad.xml")
        end.to output(/commit failed for `bad\.xml`: Errno::ENAMETOOLONG/).to_stderr_from_any_process
      end

      it "does nothing when parse_entry returns nil" do
        allow(df).to receive(:parse_entry).with(0, "skip.xml").and_return nil
        expect(df).not_to receive(:commit_doc)
        df.send(:commit_entry, 0, "skip.xml")
      end

      it "run_shard survives a failing doc and still commits the rest" do
        allow(df).to receive(:parse_entry) { |idx, file| [idx, file, :doc, :bib, {}] }
        allow(df).to receive(:commit_doc).with(:doc, :bib, "bad.xml", nil).and_raise(Errno::ENAMETOOLONG)
        expect(df).to receive(:commit_doc).with(:doc, :bib, "good.xml", nil)
        expect do
          df.send(:run_shard, ["bad.xml", "good.xml"], 0)
        end.to output(/commit failed for `bad\.xml`/).to_stderr_from_any_process
      end
    end
  end

  # it do
  #   described_class.fetch
  # end
end
