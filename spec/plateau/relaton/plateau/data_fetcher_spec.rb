# encoding: UTF-8

require "relaton/plateau/data_fetcher"

RSpec.describe Relaton::Plateau::DataFetcher do
  subject { described_class.new "data", "bibxml" }
  let(:uri) { URI "https://example.com" }

  let(:item) do
    docid = Relaton::Bib::Docidentifier.new content: "PLATEAU Handbook #01 第4.0版"
    title = Relaton::Bib::Title.new content: "Test Title", type: "main"
    Relaton::Plateau::ItemData.new docidentifier: [docid], title: [title]
  end

  it "initializes" do
    expect(subject.instance_variable_get(:@output)).to eq "data"
    expect(subject.instance_variable_get(:@format)).to eq "bibxml"
    expect(subject.instance_variable_get(:@ext)).to eq "xml"
    expect(subject.instance_variable_get(:@files)).to eq Set.new
  end

  it "index" do
    expect(Relaton::Index).to receive(:find_or_create)
      .with(:plateau, file: "index-v1.yaml").and_return :index
    expect(subject.index).to eq :index
  end

  context "fetch" do
    it "handbooks" do
      expect(subject).to receive(:extract_handbooks_data)
      subject.fetch "plateau-handbooks"
    end

    it "technical reports" do
      expect(subject).to receive(:extract_technical_reports_data)
      subject.fetch "plateau-technical-reports"
    end

    it "invalid source" do
      expect { subject.fetch "invalid" }.to output(/Invalid source: invalid/).to_stdout_from_any_process
    end
  end

  it "create_request" do
    request = subject.create_request uri
    expect(request).to be_instance_of Net::HTTP::Get
    expect(request["User-Agent"]).to eq "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:127.0) Gecko/20100101 Firefox/127.0"
    expect(request["Accept"]).to eq "*/*"
    expect(request["Accept-Language"]).to eq "en-US,en;q=0.5"
    expect(request["Accept-Encoding"]).to eq "gzip, deflate, br, zstd"
    expect(request["Referer"]).to eq "https://www.mlit.go.jp/plateau/libraries/"
    expect(request["purpose"]).to eq "prefetch"
    expect(request["x-nextjs-data"]).to eq "1"
    expect(request["Connection"]).to eq "keep-alive"
  end

  context "handle_response" do
    let(:response) { double Net::HTTPResponse, body: :body }

    it "gzip" do
      expect(response).to receive(:[]).with("Content-Encoding").and_return "gzip"
      expect(StringIO).to receive(:new).with(:body).and_return :str_io
      gz_reader = double Zlib::GzipReader
      expect(gz_reader).to receive(:read).and_return "{}"
      expect(Zlib::GzipReader).to receive(:new).with(:str_io).and_return gz_reader
      expect(subject.hadle_response(response)).to eq "{}"
    end

    it "deflate" do
      expect(response).to receive(:[]).with("Content-Encoding").and_return("deflate").twice
      expect(Zlib::Inflate).to receive(:inflate).with(:body).and_return "{}"
      expect(subject.hadle_response(response)).to eq "{}"
    end

    it "other" do
      expect(response).to receive(:[]).with("Content-Encoding").and_return(nil).twice
      expect(subject.hadle_response(response)).to eq :body
    end
  end

  context "fetch_json_data" do
    it "success" do
      url = "https://example.com"
      http = double Net::HTTP
      response = double Net::HTTPResponse, body: "{}", code: "200"
      expect(http).to receive(:request).with(an_instance_of Net::HTTP::Get).and_return response
      expect(Net::HTTP).to receive(:start).with("example.com", 443, use_ssl: true).and_yield http
      expect(subject).to receive(:hadle_response).with(response).and_return "{\"key\": \"value\"}"
      expect(subject.fetch_json_data(url)).to eq "key" => "value"
    end

    it "unsuccessful" do
      url = "https://example.com"
      http = double Net::HTTP
      response = double Net::HTTPResponse, body: "{}", code: "404", message: "Not Found"
      expect(http).to receive(:request).with(an_instance_of Net::HTTP::Get).and_return response
      expect(Net::HTTP).to receive(:start).with("example.com", 443, use_ssl: true).and_yield http
      expect do
        expect(subject.fetch_json_data(url)).to eq({})
      end.to output(/Failed to fetch data: 404 Not Found/).to_stderr_from_any_process
    end

    it "error" do
      url = "https://example.com"
      http = double Net::HTTP
      expect(http).to receive(:request).with(an_instance_of Net::HTTP::Get).and_raise StandardError
      expect(Net::HTTP).to receive(:start).with("example.com", 443, use_ssl: true).and_yield http
      expect { subject.fetch_json_data(url) }.to output(
        /Error fetching JSON data from https:\/\/example.com:/
      ).to_stderr_from_any_process
    end
  end

  context "extract data" do
    before { expect(subject.index).to receive(:save) }

    context "extract_handbooks_data" do
      let(:version) { { "title" => "第4.0版"} }
      let(:handbook) { { "title" => "Title", "description" => "Title<br />Abstract", "versions" => [version] } }
      let(:entry) { { "slug" => "01", "handbook" => handbook } }
      let(:data) { { "pageProps" => { "handbooks" => { "nodes" => [entry] } } } }

      it "handbook" do
        expect(subject).to receive(:fetch_json_data).with(
          "https://www.mlit.go.jp/plateau/_next/data/1.3.0/libraries/handbooks.json"
        ).and_return data
        expect(Relaton::Plateau::HandbookParser).to receive(:new).with(
          version: version, entry: entry, doctype: "handbook", errors: {}
        ).and_return double(parse: :bibitem)
        expect(subject).to receive(:save_document).with(:bibitem)
        subject.extract_handbooks_data
      end

      it "annex" do
        entry["slug"] = "01-01"
        expect(subject).to receive(:fetch_json_data).with(
          "https://www.mlit.go.jp/plateau/_next/data/1.3.0/libraries/handbooks.json"
        ).and_return data
        expect(Relaton::Plateau::HandbookParser).to receive(:new).with(
          version: version, entry: entry, doctype: "annex", errors: {}
        ).and_return double(parse: :bibitem)
        expect(subject).to receive(:save_document).with(:bibitem)
        subject.extract_handbooks_data
      end
    end

    it "extract_technical_reports_data" do
      data = { "pageProps" => { "nodes" => [:entry] } }
      expect(subject).to receive(:fetch_json_data).with(
        "https://www.mlit.go.jp/plateau/_next/data/1.3.0/libraries/technical-reports.json"
      ).and_return data
      expect(Relaton::Plateau::TechnicalReportParser).to receive(:new).with(:entry, kind_of(Hash))
        .and_return double(parse: :bibitem)
      expect(subject).to receive(:save_document).with(:bibitem)
      subject.extract_technical_reports_data
    end
  end

  context "save_document" do
    it "success" do
      expect(subject).to receive(:serialize).with(item).and_return "<bibxml/>"
      expect(File).to receive(:write).with(
        "data/plateau-handbook-01-40.xml", "<bibxml/>"
      )
      expect(subject.index).to receive(:add_or_update).with(
        "PLATEAU Handbook #01 第4.0版", "data/plateau-handbook-01-40.xml"
      )
      subject.save_document item
      expect(subject.instance_variable_get(:@files)).to eq Set.new(["data/plateau-handbook-01-40.xml"])
    end

    it "duplicate" do
      subject.instance_variable_set :@files, Set.new(["data/plateau-handbook-01-40.xml"])
      expect(File).not_to receive(:write)
      subject.save_document item
    end
  end

  context "file_name" do
    it do
      expect(subject.file_name("PLATEAU Handbook #01 第4.0版"))
        .to eq "data/plateau-handbook-01-40.xml"
    end

    it "private" do
      expect(subject.file_name("PLATEAU Handbook #11 第1.0版（民間活用編）"))
        .to eq "data/plateau-handbook-11-10-private.xml"
    end

    it "public" do
      expect(subject.file_name("PLATEAU Handbook #11 第1.0版（公共活用編）"))
        .to eq "data/plateau-handbook-11-10-public.xml"
    end
  end

  context "serialize" do
    it "yaml" do
      subject.instance_variable_set :@format, "yaml"
      subject.instance_variable_set :@ext, "yaml"
      yaml_output = subject.to_yaml item
      expect(yaml_output).to include "PLATEAU Handbook #01"
    end

    it "xml" do
      xml_output = subject.to_xml item
      expect(xml_output).to include "PLATEAU Handbook #01"
    end

    it "bibxml" do
      rfcxml_output = subject.to_bibxml item
      expect(rfcxml_output).to include "<reference"
    end
  end
end
