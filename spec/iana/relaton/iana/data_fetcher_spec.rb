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

      it "skip" do
        expect(subject).not_to receive(:output_file)
        subject.send :save_doc, nil
      end

      it "bibxml" do
        subject = described_class.new("dir", "bibxml")
        expect(File).to receive(:write).with("dir/bib.xml", /anchor=/, encoding: "UTF-8")
        subject.send :save_doc, bib
        expect(index.index).to eq [{ id: "BIB", file: "dir/bib.xml" }]
      end

      it "xml" do
        expect(File).to receive(:write).with("dir/bib.xml", /<bibdata/, encoding: "UTF-8")
        subject.send :save_doc, bib
        expect(index.index).to eq [{ id: "BIB", file: "dir/bib.xml" }]
      end

      it "yaml" do
        subject = described_class.new("dir", "yaml")
        expect(File).to receive(:write).with("dir/bib.yaml", /docnumber: BIB/, encoding: "UTF-8")
        subject.send :save_doc, bib
        expect(index.index).to eq [{ id: "BIB", file: "dir/bib.yaml" }]
      end

      it "warn when file exists" do
        subject.instance_variable_set(:@files, ["dir/bib.xml"])
        expect(File).to receive(:write).with("dir/bib.xml", /<bibdata/, encoding: "UTF-8")
        expect do
          subject.send :save_doc, bib
        end.to output(/File dir\/bib.xml already exists/).to_stderr_from_any_process
        expect(index.index).to eq [{ id: "BIB", file: "dir/bib.xml" }]
      end
    end
  end

  # it do
  #   described_class.fetch format: "bibxml"
  # end
end
