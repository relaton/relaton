require "relaton/iana/data_fetcher"

RSpec.describe Relaton::Iana::DataFetcher do
  it "create output dir and run fetcher" do
    expect(FileUtils).to receive(:mkdir_p).with("dir")
    fetcher = double("fetcher")
    expect(fetcher).to receive(:fetch)
    expect(described_class)
      .to receive(:new).with("dir", "xml").and_return(fetcher)
    allow(fetcher).to receive(:digest_ledger=)
    described_class.fetch output: "dir", format: "xml"
  end

  context "instance" do
    subject { described_class.new("dir", "xml") }
    let(:index) { subject.send(:index) }

    context "fetch data" do
      before do
        expect(Dir).to receive(:[]).with("iana-registries/**/*.xml").and_return ["file.xml"]
        expect(index).to receive(:save)
      end

      it "successfully" do
        expect(File).to receive(:read).with("file.xml", encoding: "UTF-8").and_return("<registry></registry>")
        expect(subject).to receive(:collect).with("<registry></registry>", kind_of(Array))
        subject.fetch
      end

      it "warn when error" do
        expect(File).to receive(:read).with("file.xml", encoding: "UTF-8").and_raise(StandardError)
        expect { subject.fetch }.to output(/Error: StandardError\. File: file\.xml/).to_stderr_from_any_process
      end
    end

    # A <hide/> page wrapper with no <record> children of its own (IANA nests
    # the real registry inside it as a same-titled "-1" child), and a
    # standalone page republished empty beside the umbrella that holds the
    # records: both used to become slug-titled, dateless duplicate documents
    # (relaton-iana#8, #9). Neither becomes a document now; the empty
    # standalone aliases the record-bearing document of its own registry id.
    context "record-less registries" do
      let(:wrapper_xml) do
        <<~XML
          <registry xmlns="http://www.iana.org/assignments" id="language-tag-extensions-registry">
            <hide/>
            <title>Language Tag Extensions Registry</title>
            <registry id="language-tag-extensions-registry-1">
              <title>Language Tag Extensions Registry</title>
              <record>
                <value>inf</value>
                <description>Obsolete</description>
              </record>
            </registry>
          </registry>
        XML
      end

      let(:umbrella_xml) do
        <<~XML
          <registry xmlns="http://www.iana.org/assignments" id="rpki">
            <title>Resource Public Key Infrastructure (RPKI)</title>
            <record>
              <value>rpki</value>
              <description>RPKI umbrella</description>
            </record>
            <registry id="signed-objects">
              <title>RPKI Signed Objects</title>
              <record>
                <value>1</value>
                <description>Signed object</description>
              </record>
            </registry>
          </registry>
        XML
      end

      let(:standalone_xml) do
        <<~XML
          <registry xmlns="http://www.iana.org/assignments" id="rpki-signed-objects">
            <title>rpki-signed-objects</title>
          </registry>
        XML
      end

      def fetched_rows
        Relaton::Index.find_or_create(:iana, file: "index-v2.yaml",
                                            pubid_class: ::Pubid::Iana::Identifier)
                      .index.map { |r| [r[:id].to_s, r[:file]] }
      end

      it "keeps only the record-bearing document of a wrapped registry" do
        Dir.mktmpdir do |tmp|
          Dir.chdir(tmp) do
            FileUtils.mkdir_p "iana-registries"
            File.write "iana-registries/wrapper.xml", wrapper_xml
            described_class.fetch output: "out", format: "yaml"

            expect(Dir["out/*.yaml"].map { |f| File.basename(f) })
              .to eq ["language-tag-extensions-registry-language-tag-extensions-registry-1.yaml"]
          end
        end
      end

      it "aliases an empty standalone to the record-bearing document of its id" do
        Dir.mktmpdir do |tmp|
          Dir.chdir(tmp) do
            FileUtils.mkdir_p "iana-registries"
            File.write "iana-registries/rpki.xml", umbrella_xml
            File.write "iana-registries/rpki-signed-objects.xml", standalone_xml
            described_class.fetch output: "out", format: "yaml"

            expect(Dir["out/*.yaml"].size).to eq 2
            expect(fetched_rows).to contain_exactly(
              ["IANA rpki", "out/rpki.yaml"],
              ["IANA rpki/signed-objects", "out/rpki-signed-objects.yaml"],
              ["IANA rpki-signed-objects", "out/rpki-signed-objects.yaml"],
            )
          end
        end
      end

      it "skips a registry whose source is unchanged since the last run" do
        Dir.mktmpdir do |tmp|
          Dir.chdir(tmp) do
            FileUtils.mkdir_p "iana-registries"
            File.write "iana-registries/rpki.xml", umbrella_xml
            described_class.fetch output: "out", format: "yaml", digest_ledger: true
            first_mtime = File.mtime("out/rpki.yaml")
            expect(YAML.load_file("out/.digests.yaml").keys).to include("rpki")

            described_class.fetch output: "out", format: "yaml", digest_ledger: true
            expect(File.mtime("out/rpki.yaml")).to eq(first_mtime)
          end
        end
      end

      it "drops an empty standalone with no record-bearing twin" do
        Dir.mktmpdir do |tmp|
          Dir.chdir(tmp) do
            FileUtils.mkdir_p "iana-registries"
            File.write "iana-registries/empty.xml", standalone_xml
            expect { described_class.fetch output: "out", format: "yaml" }
              .to output(/rpki-signed-objects has no records; skipping/).to_stderr_from_any_process

            expect(Dir["out/*.yaml"]).to be_empty
            expect(fetched_rows).to be_empty
          end
        end
      end
    end

    context "save doc" do
      let(:bib) { Relaton::Iana::ItemData.new(docnumber: "BIB") }

      # index-v2 rows hold Pubid::Iana identifier objects, not strings; compare
      # the serialized hash so a failure prints something readable.
      def indexed
        index.index.map { |r| { id: r[:id].to_hash, file: r[:file] } }
      end

      it "skip" do
        expect(subject).not_to receive(:output_file)
        subject.send :save_doc, nil
      end

      it "bibxml" do
        subject = described_class.new("dir", "bibxml")
        expect(File).to receive(:write).with("dir/bib.xml", /anchor=/, encoding: "UTF-8")
        subject.send :save_doc, bib
        expect(indexed).to eq [{ id: { "_type" => "pubid:iana:registry", "number" => "BIB" },
                                 file: "dir/bib.xml" }]
      end

      it "xml" do
        expect(File).to receive(:write).with("dir/bib.xml", /<bibdata/, encoding: "UTF-8")
        subject.send :save_doc, bib
        expect(indexed).to eq [{ id: { "_type" => "pubid:iana:registry", "number" => "BIB" },
                                 file: "dir/bib.xml" }]
      end

      it "yaml" do
        subject = described_class.new("dir", "yaml")
        expect(File).to receive(:write).with("dir/bib.yaml", /docnumber: BIB/, encoding: "UTF-8")
        subject.send :save_doc, bib
        expect(indexed).to eq [{ id: { "_type" => "pubid:iana:registry", "number" => "BIB" },
                                 file: "dir/bib.yaml" }]
      end

      it "skips an index entry whose docnumber pubid cannot parse" do
        # Relaton::Index rejects the WHOLE index if one row fails to
        # deserialize, so a bad slug must never reach it.
        bad = Relaton::Iana::ItemData.new(docnumber: "not a slug")
        expect(File).to receive(:write)
        # The Type is pooled, so count the delta rather than asserting empty.
        before = index.index.size
        expect do
          subject.send :save_doc, bad
        end.to output(/Skipping index entry for `not a slug`/).to_stderr_from_any_process
        expect(index.index.size).to eq before
      end

      it "gives a colliding docnumber a file of its own" do
        # `output_file` collapses "/" and "-" alike, so `rpki/signed-objects`
        # and `rpki-signed-objects` both want data/rpki-signed-objects.yaml.
        # Warning and writing anyway left one file holding the wrong document
        # for one of two index ids.
        a = Relaton::Iana::ItemData.new(docnumber: "rpki/signed-objects")
        b = Relaton::Iana::ItemData.new(docnumber: "rpki-signed-objects")
        written = []
        allow(File).to receive(:write) { |f, *| written << f }
        before = index.index.size

        subject.send :save_doc, a
        expect { subject.send :save_doc, b }
          .to output(/already exists/).to_stderr_from_any_process

        expect(written.uniq.size).to eq 2
        expect(index.index.size).to eq before + 2
        files = index.index.last(2).map { |r| r[:file] }
        expect(files.uniq.size).to eq 2
        expect(files).to include "dir/rpki-signed-objects.xml"
      end

      it "warn when file exists" do
        subject.instance_variable_set(:@files, ["dir/bib.xml"])
        expect(File).to receive(:write).with("dir/bib.xml", /<bibdata/, encoding: "UTF-8")
        expect do
          subject.send :save_doc, bib
        end.to output(/File dir\/bib.xml already exists/).to_stderr_from_any_process
        expect(indexed).to eq [{ id: { "_type" => "pubid:iana:registry", "number" => "BIB" },
                                 file: "dir/bib.xml" }]
      end
    end
  end

  # it do
  #   described_class.fetch format: "bibxml"
  # end
end
