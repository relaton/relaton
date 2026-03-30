require "relaton/bipm/data_fetcher"

describe Relaton::Bipm::DataFetcher do
  it "call new and fetch" do
    # expect(Dir).to receive(:exist?).with("data").and_return false
    expect(FileUtils).to receive(:mkdir_p).with("data")
    fetcher = double("fetcher")
    expect(fetcher).to receive(:fetch).with "bipm-data-outcomes"
    expect(described_class).to receive(:new).with("data", "yaml").and_return fetcher
    described_class.fetch "bipm-data-outcomes"
  end

  it "initialize" do
    # expect(Relaton::Index).to receive(:find_or_create).with(:bipm, file: "index.yaml").and_return({})
    fetcher = described_class.new "data", "bibxml"
    expect(fetcher.instance_variable_get(:@output)).to eq "data"
    expect(fetcher.instance_variable_get(:@format)).to eq "bibxml"
    expect(fetcher.instance_variable_get(:@ext)).to eq "xml"
    expect(fetcher.instance_variable_get(:@files)).to be_instance_of Set
    # expect(fetcher.instance_variable_get(:@index)).to eq({})
  end

  context "instance methods" do
    subject { described_class.new "data", "yaml" }
    let(:docidentifier) { Relaton::Bib::Docidentifier.new(type: "BIPM", content: "1234") }
    let(:item) { Relaton::Bipm::ItemData.new docidentifier: [docidentifier] }

    # before :each do
    #   expect(File).to receive(:exist?).with("index.yaml").and_return false
    #   allow(File).to receive(:exist?).and_call_original
    # end

    it "#report_errors" do
      errors = subject.instance_variable_get(:@errors)
      errors[:title] = true
      expect(subject).to receive(:report_errors)
      subject.report_errors
    end

    context "#fetch" do
      before(:each) do
        expect(subject.index).to receive(:save)
        expect(subject).to receive(:report_errors)
      end

      it "bipm-datata-outcomes" do
        expect(Relaton::Bipm::DataOutcomesParser).to receive(:parse).with subject
        subject.fetch "bipm-data-outcomes"
      end

      it "bipm-si-brochure" do
        expect(Relaton::Bipm::SiBrochureParser).to receive(:parse).with subject
        subject.fetch "bipm-si-brochure"
      end

      it "rawdata-bipm-metrologia" do
        expect(Relaton::Bipm::RawdataBipmMetrologia::Fetcher).to receive(:fetch).with subject
        subject.fetch "rawdata-bipm-metrologia"
      end
    end

    context "#write_file" do
      let(:path) { "data/cgpm/meeting/1889-00.yaml" }

      before :each do
        expect(File).to receive(:write).with(path, kind_of(String), encoding: "UTF-8")
      end

      it "without duplicate" do
        subject.write_file path, item
        expect(subject.instance_variable_get(:@files)).to include path
      end

      it "with duplicate" do
        expect do
          subject.instance_variable_set(:@files, [path])
          subject.write_file path, item
        end.to output("[relaton-bipm] WARN: File #{path} already exists\n").to_stderr_from_any_process
      end

      it "with duplicate and warn_duplicate: false" do
        expect do
          subject.instance_variable_set(:@files, [path])
          subject.write_file path, item, warn_duplicate: false
        end.not_to output("File #{path} already exists\n").to_stderr_from_any_process
      end
    end

    context "#serialize" do
      it "xml" do
        subject.instance_variable_set(:@format, "xml")
        expect(subject.serialize(item)).to include "<docidentifier type=\"BIPM\">1234</docidentifier>"
      end

      it "yaml" do
        expect(subject.serialize(item)).to include "type: BIPM"
      end

      it "bibxml" do
        subject.instance_variable_set(:@format, "bibxml")
        expect(subject.serialize(item)).to include '<reference anchor="1234">'
      end
    end
  end
end
