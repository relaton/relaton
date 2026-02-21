require "relaton/itu/data_fetcher"

describe Relaton::Itu::DataFetcher do
  it "::fetch" do
    expect(FileUtils).to receive(:mkdir_p).with("data")
    df = double "df"
    expect(df).to receive(:fetch).with(nil)
    expect(described_class).to receive(:new).with("data", "yaml").and_return df
    described_class.fetch
  end

  context "instance methods" do
    subject { described_class.new "data", "yaml" }

    it("#index") { expect(subject.index).to be_instance_of Relaton::Index::Type }
    it("#agent") { expect(subject.agent).to be_instance_of Mechanize }
    it("#workers") { expect(subject.workers).to be_instance_of Relaton::Core::WorkersPool }

    context "#parse_page" do
      it do
        expect(subject.agent).to receive(:get).with(:url).and_return :doc
        expect(Relaton::Itu::DataParserR).to receive(:parse).with(:doc, :url, :type).and_return :bib
        expect(subject).to receive(:write_file).with(:bib)
        subject.parse_page :url, :type
      end

      it "rescue" do
        expect(subject.agent).to receive(:get).with(:url).and_raise "error"
        expect do
          subject.parse_page :url, :type
        end.to output(/error/).to_stderr_from_any_process
      end
    end

    it "#fetch" do
      expect(subject).to receive(:fetch_recommendation)
      expect(subject).to receive(:fetch_question)
      expect(subject).to receive(:fetch_report)
      expect(subject).to receive(:fetch_handbook)
      expect(subject).to receive(:fetch_resolution)
      expect(subject.workers).to receive(:end)
      expect(subject.workers).to receive(:result)
      expect(subject.index).to receive(:save)
      subject.fetch
    end

    it "#fetch_recommendation" do
      expect(subject).to receive(:json_index).with(kind_of(String), "recommendation")
      subject.fetch_recommendation
    end

    it "#fetch_question" do
      expect(subject).to receive(:html_index).with(kind_of(String), "question")
      subject.fetch_question
    end

    it "#fetch_report" do
      expect(subject).to receive(:json_index).with(kind_of(String), "technical-report")
      subject.fetch_report
    end

    it "#fetch_handbook" do
      expect(subject).to receive(:html_index).with(kind_of(String), "handbook")
      subject.fetch_handbook
    end

    it "#fetch_resolution" do
      expect(subject).to receive(:html_index).with(kind_of(String), "resolution")
      subject.fetch_resolution
    end

    context "#json_index" do
      let(:url) { "http://extranet.itu.int/Paged=1" }

      before do
        result = double "result", body: :body
        expect(subject.agent).to receive(:post).with(url).and_return result
        expect(subject.workers).to receive(:<<).with(["page_url", :type])
      end

      it "no next page" do
        expect(JSON).to receive(:parse).with(:body).and_return "Row" => [
          { "serverurl.progid" => "1page_url" },
        ]
        subject.json_index url, :type
      end

      it "next page" do
        expect(JSON).to receive(:parse).with(:body).and_return "Row" => [
          { "serverurl.progid" => "1page_url" },
        ], "NextHref" => "aspx?Paged=2"
        expect(subject).to receive(:json_index).with("http://extranet.itu.int/Paged=1", :type).and_call_original
        expect(subject).to receive(:json_index).with("http://extranet.itu.int/Paged=2", :type)
        subject.json_index url, :type
      end
    end

    it "#html_index" do
      body = <<~HTML
        <html>
          <body>
            <table>
              <table>
                <tr></tr>
                <tr><td><a onclick="https://extranet.itu.int'">title</a></td></tr>
              </table>
            </table>
          </body>
        </html>
      HTML
      resp = double "resp", body: body
      expect(subject.agent).to receive(:get).with(:url).and_return resp
      expect(subject.workers).to receive(:<<).with(["https://extranet.itu.int", :type])
      subject.html_index :url, :type
    end

    context "#write_file" do
      let(:bib) do
        docid = double "docid", content: "ITU 123.4", type: "ITU"
        double "bib", docidentifier: [docid]
      end

      before do
        expect(subject).to receive(:serialize).with(bib).and_return :content
        expect(File).to receive(:write).with("data/ITU_123_4.yaml", :content, encoding: "UTF-8")
      end

      it do
        subject.write_file bib
        expect(subject.instance_variable_get(:@files)).to eq Set["data/ITU_123_4.yaml"]
      end

      it "file exists" do
        subject.instance_variable_set :@files, Set["data/ITU_123_4.yaml"]
        expect do
          subject.write_file bib
        end.to output(/File data\/ITU_123_4.yaml exists./).to_stderr_from_any_process
      end
    end

    context "#to_yaml" do
      let(:bib) { double "bib" }

      it do
        hash = double "hash"
        expect(bib).to receive(:to_hash).and_return hash
        expect(hash).to receive(:to_yaml).and_return :yaml
        expect(subject.to_yaml(bib)).to eq :yaml
      end
    end

    context "#to_xml" do
      let(:bib) { double "bib" }

      it do
        expect(bib).to receive(:to_xml).with(bibdata: true).and_return :xml
        expect(subject.to_xml(bib)).to eq :xml
      end
    end

    context "#to_bibxml" do
      let(:bib) { double "bib" }

      it do
        expect(bib).to receive(:to_bibxml).and_return :bibxml
        expect(subject.to_bibxml(bib)).to eq :bibxml
      end
    end
  end
end
