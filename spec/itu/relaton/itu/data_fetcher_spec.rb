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
    let(:bib) do
      Relaton::Itu::ItemData.new(
        docidentifier: [Relaton::Itu::Docidentifier.new(type: "ITU", content: "ITU-R M.1234", primary: true)],
        title: [Relaton::Bib::Title.new(type: "main", content: "Test title", language: "en", script: "Latn")],
        language: ["en"], script: ["Latn"], type: "standard",
        ext: Relaton::Itu::Ext.new(doctype: Relaton::Itu::Doctype.new(content: "recommendation")),
      )
    end

    subject { described_class.new "data", "yaml" }

    it("#index") { expect(subject.index).to be_instance_of Relaton::Index::Type }

    context "#fetch" do
      it "paginates through search results" do
        bib = double "bib"
        result1 = { "Title" => "ITU-R M.1" }
        result2 = { "Title" => "ITU-R M.2" }

        expect(subject).to receive(:search_request).with(0).and_return [result1, result2]
        expect(subject).to receive(:search_request).with(100).and_return []
        expect(subject).to receive(:search_request).with(200).and_return []
        expect(subject).to receive(:search_request).with(300).and_return []

        expect(Relaton::Itu::DataParserR).to receive(:parse).with(result1, kind_of(Hash)).and_return bib
        expect(Relaton::Itu::DataParserR).to receive(:parse).with(result2, kind_of(Hash)).and_return nil

        expect(subject).to receive(:write_file).with(bib).once
        expect(subject.index).to receive(:save)

        subject.fetch
      end

      it "skips empty pages and continues fetching" do
        bib = double "bib"
        result1 = { "Title" => "ITU-R M.1" }
        result2 = { "Title" => "ITU-R M.2" }

        expect(subject).to receive(:search_request).with(0).and_return [result1]
        expect(subject).to receive(:search_request).with(100).and_return []
        expect(subject).to receive(:search_request).with(200).and_return [result2]
        expect(subject).to receive(:search_request).with(300).and_return []
        expect(subject).to receive(:search_request).with(400).and_return []
        expect(subject).to receive(:search_request).with(500).and_return []

        expect(Relaton::Itu::DataParserR).to receive(:parse).with(result1, kind_of(Hash)).and_return bib
        expect(Relaton::Itu::DataParserR).to receive(:parse).with(result2, kind_of(Hash)).and_return bib

        expect(subject).to receive(:write_file).with(bib).twice
        expect(subject.index).to receive(:save)

        subject.fetch
      end

      it "handles parse errors gracefully" do
        result = { "Title" => "ITU-R M.1" }
        expect(subject).to receive(:search_request).with(0).and_return [result]
        expect(subject).to receive(:search_request).with(100).and_return []
        expect(subject).to receive(:search_request).with(200).and_return []
        expect(subject).to receive(:search_request).with(300).and_return []
        expect(Relaton::Itu::DataParserR).to receive(:parse).with(result, kind_of(Hash)).and_raise "parse error"
        expect(subject.index).to receive(:save)

        expect { subject.fetch }.to output(/parse error/).to_stderr_from_any_process
      end
    end

    context "#search_request" do
      it "sends POST with correct parameters" do
        response = double "response", body: '{"results": [{"Title": "ITU-R M.1"}]}'
        http = double "http"
        expect(Net::HTTP).to receive(:new).with("www.itu.int", 443).and_return http
        expect(http).to receive(:use_ssl=).with(true)
        expect(http).to receive(:request) do |req|
          expect(req).to be_instance_of Net::HTTP::Post
          expect(req["Content-Type"]).to eq "application/x-www-form-urlencoded; charset=UTF-8"
          expect(req["X-Requested-With"]).to eq "XMLHttpRequest"
          expect(req["Referer"]).to eq "https://www.itu.int/net4/itu-t/search/"
          expect(req.body).to start_with("json=")
          payload = JSON.parse(URI.decode_www_form_component(req.body.sub(/^json=/, "")))
          expect(payload["Start"]).to eq 0
          expect(payload["Rows"]).to eq 100
          expect(payload["CollectionName"]).to eq "ITU-R Publications"
          response
        end

        results = subject.send(:search_request, 0)
        expect(results).to eq [{ "Title" => "ITU-R M.1" }]
      end

      it "returns empty array when no results key" do
        response = double "response", body: '{}'
        http = double "http"
        expect(Net::HTTP).to receive(:new).and_return http
        expect(http).to receive(:use_ssl=)
        expect(http).to receive(:request).and_return response

        expect(subject.send(:search_request, 0)).to eq []
      end
    end

    context "#write_file" do
      before do
        expect(subject).to receive(:serialize).with(bib).and_return :content
        expect(File).to receive(:write).with("data/itu-r-m-1234.yaml", :content, encoding: "UTF-8")
      end

      it do
        subject.write_file bib
        expect(subject.instance_variable_get(:@files)).to eq Set["data/itu-r-m-1234.yaml"]
      end

      it "file exists" do
        subject.instance_variable_set :@files, Set["data/itu-r-m-1234.yaml"]
        expect do
          subject.write_file bib
        end.to output(/File data\/itu-r-m-1234\.yaml exists./).to_stderr_from_any_process
      end
    end

    context "serialization" do
      it("#to_yaml") { expect(subject.to_yaml(bib)).to be_instance_of String }
      it("#to_xml") { expect(subject.to_xml(bib)).to include("<bibdata") }
      it("#to_bibxml") { expect(subject.to_bibxml(bib)).to include("<reference") }
    end
  end
end
