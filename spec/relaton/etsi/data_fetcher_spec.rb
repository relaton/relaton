require "relaton/etsi/data_fetcher"

describe Relaton::Etsi::DataFetcher do
  let(:docid) { Relaton::Bib::Docidentifier.new type: "ETSI", content: "ETSI A/12 ed.1 (2019-10)" }
  let(:item) { Relaton::Bib::ItemData.new docidentifier: [docid] }
  subject { Relaton::Etsi::DataFetcher.new "dir", "xml" }

  it "initilizes" do
    expect(subject.instance_variable_get(:@output)).to eq "dir"
    expect(subject.instance_variable_get(:@format)).to eq "xml"
    expect(subject.instance_variable_get(:@ext)).to eq "xml"
  end

  context "fetches" do
    it "default output & format" do
      expect(FileUtils).to receive(:mkdir_p).with("data")
      data_fetcher = double "data_fetcher"
      expect(data_fetcher).to receive(:fetch)
      expect(described_class).to receive(:new).with("data", "yaml").and_return data_fetcher
      described_class.fetch
    end
  end

  context "instance methods" do
    it "#index1" do
      expect(subject.index).to be_instance_of Relaton::Index::Type
    end

    it "#fetch" do
      agent = double("mechanize")
      expect(Mechanize).to receive(:new).and_return agent
      expect(agent).to receive(:get).with(kind_of(String)).and_return double("page", body: "sep=;\r\n\"id\";\r\n\"12\";\r\n")
      data_parser = double "data_parser"
      expect(data_parser).to receive(:parse).and_return :bibitem
      expect(Relaton::Etsi::DataParser).to receive(:new).with(kind_of(CSV::Row)).and_return data_parser
      expect(subject).to receive(:save).with(:bibitem)
      expect(subject.index).to receive(:save)
      subject.fetch
    end

    it "#save" do
      expect(File).to receive(:write).with("dir/ETSI_A-12_ed_1_2019-10.xml", kind_of(String), encoding: "UTF-8")
      expect(subject.index).to receive(:add_or_update).with("ETSI A/12 ed.1 (2019-10)", "dir/ETSI_A-12_ed_1_2019-10.xml")
      subject.save item
    end

    context "#fetch_with_retry" do
      let(:agent) { double("mechanize") }
      let(:url) { "http://example.com" }

      before do
        allow(Mechanize).to receive(:new).and_return(agent)
        allow(subject).to receive(:sleep)
      end

      it "retries on network error and succeeds" do
        expect(agent).to receive(:get).with(url).and_raise(Net::OpenTimeout)
        expect(agent).to receive(:get).with(url)
          .and_return(double(body: "csv content"))
        expect(Relaton::Etsi::Util).to receive(:info)
          .with(/Fetch failed.*retrying \(1\/3\)/)

        result = subject.fetch_with_retry(url)
        expect(result).to eq("csv content")
      end

      it "retries multiple times before succeeding" do
        expect(agent).to receive(:get).with(url).and_raise(SocketError).twice
        expect(agent).to receive(:get).with(url)
          .and_return(double(body: "csv content"))
        expect(Relaton::Etsi::Util).to receive(:info)
          .with(/retrying \(1\/3\)/).ordered
        expect(Relaton::Etsi::Util).to receive(:info)
          .with(/retrying \(2\/3\)/).ordered

        result = subject.fetch_with_retry(url)
        expect(result).to eq("csv content")
      end

      it "raises after exhausting retries" do
        expect(agent).to receive(:get).with(url)
          .and_raise(Errno::ECONNRESET).exactly(4).times
        expect(Relaton::Etsi::Util).to receive(:info).exactly(3).times

        expect { subject.fetch_with_retry(url) }
          .to raise_error(Errno::ECONNRESET)
      end

      it "applies increasing delay between retries" do
        expect(agent).to receive(:get).with(url)
          .and_raise(Net::ReadTimeout).twice
        expect(agent).to receive(:get).with(url)
          .and_return(double(body: "content"))
        allow(Relaton::Etsi::Util).to receive(:info)

        expect(subject).to receive(:sleep).with(2).ordered
        expect(subject).to receive(:sleep).with(4).ordered

        subject.fetch_with_retry(url)
      end
    end

    context "#serialize" do
      it "xml" do
        expect(subject.serialize(item)).to include(
          "<docidentifier type=\"ETSI\">ETSI A/12 ed.1 (2019-10)</docidentifier>",
        )
      end

      it "yaml" do
        subject.instance_variable_set :@format, "yaml"
        expect(subject.serialize(item)).to include "content: ETSI A/12 ed.1 (2019-10)"
      end

      it "bibxml" do
        subject.instance_variable_set :@format, "bibxml"
        expect(subject.serialize(item)).to include '<reference anchor="ETSI.A/12.ed.1.(2019-10)">'
      end
    end
  end
end
