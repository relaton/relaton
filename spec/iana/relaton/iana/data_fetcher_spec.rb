require "relaton/iana/data_fetcher"

RSpec.describe Relaton::Iana::DataFetcher do
  it "create output dir and run fetcher" do
    expect(FileUtils).to receive(:mkdir_p).with("dir")
    fetcher = double("fetcher")
    expect(fetcher).to receive(:fetch)
    expect(described_class)
      .to receive(:new).with("dir", "xml").and_return(fetcher)
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
        expect(subject).to receive(:parse).with("<registry></registry>")
        subject.fetch
      end

      it "warn when error" do
        expect(File).to receive(:read).with("file.xml", encoding: "UTF-8").and_raise(StandardError)
        expect { subject.fetch }.to output(/Error: StandardError\. File: file\.xml/).to_stderr_from_any_process
      end
    end

    it "parse" do
      content = File.read "fixtures/rpki.xml", encoding: "UTF-8"
      expect(Relaton::Iana::Parser).to receive(:parse).with(Nokogiri::XML::Element, nil, kind_of(Hash)).and_return :doc
      expect(subject).to receive(:save_doc).with(:doc)
      expect(Relaton::Iana::Parser).to receive(:parse).with(Nokogiri::XML::Element, :doc, kind_of(Hash)).and_return(:doc2).exactly(7).times
      expect(subject).to receive(:save_doc).with(:doc2).exactly(7).times
      subject.send :parse, content
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
