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
      .with(:plateau, file: "index-v2.yaml", pubid_class: ::Pubid::Plateau::Identifier)
      .and_return :index
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
        ).and_return double(parse: item)
        expect(subject).to receive(:save_document).with(item)
        subject.extract_handbooks_data
      end

      it "annex" do
        entry["slug"] = "01-01"
        expect(subject).to receive(:fetch_json_data).with(
          "https://www.mlit.go.jp/plateau/_next/data/1.3.0/libraries/handbooks.json"
        ).and_return data
        expect(Relaton::Plateau::HandbookParser).to receive(:new).with(
          version: version, entry: entry, doctype: "annex", errors: {}
        ).and_return double(parse: item)
        expect(subject).to receive(:save_document).with(item)
        subject.extract_handbooks_data
      end
    end

    # relaton-plateau#13: the split editions 1-3 of Handbook #11 are
    # saved as Handbook #04 and #06, and no edition is skipped.
    it "splits Handbook #11 editions 1-3 into Handbook #04 and #06" do
      versions = %w[第4.0版 第3.0版（公共活用編） 第3.0版（民間活用編） 第2.0版（公共活用編）
                    第2.0版（民間活用編） 第1.0版（公共活用編） 第1.0版（民間活用編）].map do |title|
        { "title" => title, "date" => "2021.3.26", "filesize" => "1", "pdf" => "https://example.com/x.pdf" }
      end
      handbook = {
        "title" => "3D都市モデルのユースケース開発マニュアル", "description" => "Abstract",
        "thumbnail" => { "mediaItemUrl" => "/plateau/uploads/plateau_doc_0011_ver04.jpg" },
        "versions" => versions
      }
      data = { "pageProps" => { "handbooks" => { "nodes" => [{ "slug" => "11", "handbook" => handbook }] } } }
      allow(subject).to receive(:fetch_json_data).and_return data
      allow(subject).to receive(:serialize).and_return "<bibxml/>"
      allow(subject.index).to receive(:save)
      files = []
      allow(File).to receive(:write) { |file, _| files << file }
      ids = []
      allow(subject.index).to receive(:add_or_update) { |pid, _| ids << pid.to_s }
      expect { subject.extract_handbooks_data }.not_to output(/already exists/).to_stderr_from_any_process
      expect(ids).to contain_exactly(
        "PLATEAU Handbook #11 第4.0版",
        "PLATEAU Handbook #04 第3.0版", "PLATEAU Handbook #06 第3.0版",
        "PLATEAU Handbook #04 第2.0版", "PLATEAU Handbook #06 第2.0版",
        "PLATEAU Handbook #04 第1.0版", "PLATEAU Handbook #06 第1.0版",
      )
      expect(files.uniq.size).to eq 7
    end

    # Handbook #00 lists edition 5.0 twice: 本編 (main volume) and
    # 本編＋付録 (main volume and appendix), two publications. Each version
    # keeps the source's volume label in its id, and gets its own file.
    it "saves each volume of an edition as its own record" do
      pdf = "https://www.mlit.go.jp/plateau/file/libraries/doc/plateau_doc_%s.pdf"
      versions = [
        ["第6.0版　本編＋付録", "0000_ver06"], ["第5.0版　本編", "0000_ver05"],
        ["第5.0版　本編＋付録", "00001_ver05"], ["第4.0版", "0000_ver04"]
      ].map do |title, file|
        { "title" => title, "date" => "2025.3.31", "filesize" => "1", "pdf" => format(pdf, file) }
      end
      handbook = {
        "title" => "PLATEAU Guidebook", "description" => "Abstract",
        "thumbnail" => { "mediaItemUrl" => "/plateau/uploads/plateau_doc_0000_ver06.jpg" },
        "versions" => versions
      }
      data = { "pageProps" => { "handbooks" => { "nodes" => [{ "slug" => "00", "handbook" => handbook }] } } }
      allow(subject).to receive(:fetch_json_data).and_return data
      allow(subject).to receive(:serialize).and_return "<bibxml/>"
      allow(subject.index).to receive(:save)
      files = []
      allow(File).to receive(:write) { |file, _| files << File.basename(file) }
      rows = {}
      allow(subject.index).to receive(:add_or_update) { |pid, file| rows[pid.to_s] = File.basename(file) }
      expect { subject.extract_handbooks_data }.not_to output(/already exists/).to_stderr_from_any_process
      expect(rows).to eq(
        "PLATEAU Handbook #00 第6.0版 本編＋付録" => "plateau-handbook-00-60-with-appendix.xml",
        "PLATEAU Handbook #00 第5.0版 本編" => "plateau-handbook-00-50-main.xml",
        "PLATEAU Handbook #00 第5.0版 本編＋付録" => "plateau-handbook-00-50-with-appendix.xml",
        "PLATEAU Handbook #00 第4.0版" => "plateau-handbook-00-40.xml",
      )
      expect(files).to eq rows.values
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
      # The canonical id is stored as a Pubid::Plateau::Identifier, not a string.
      expect(subject.index).to receive(:add_or_update) do |pid, file|
        expect(pid).to be_a ::Pubid::Plateau::Identifier
        expect(pid.to_s).to eq "PLATEAU Handbook #01 第4.0版"
        expect(file).to eq "data/plateau-handbook-01-40.xml"
      end
      subject.save_document item
      expect(subject.instance_variable_get(:@files)).to eq Set.new(["data/plateau-handbook-01-40.xml"])
    end

    it "skips (and warns about) an id pubid cannot parse" do
      docid = Relaton::Bib::Docidentifier.new content: "PLATEAU Bogus #99" # not a PLATEAU id
      bad = Relaton::Plateau::ItemData.new docidentifier: [docid]
      expect(subject).to receive(:serialize).with(bad).and_return "<bibxml/>"
      expect(File).to receive(:write)
      expect(subject.index).not_to receive(:add_or_update)
      expect { subject.save_document bad }.to output(/Unparseable id `PLATEAU Bogus #99`/)
        .to_stderr_from_any_process
    end

    # The data repo crawls incrementally: it keeps data/ and calls
    # prune_unwritten, which deletes only what the run did not record.
    it "records the file, so prune_unwritten deletes only stale files" do
      Dir.mktmpdir do |dir|
        fetcher = described_class.new dir, "yaml"
        allow(fetcher.index).to receive(:add_or_update)
        allow(fetcher).to receive(:serialize).and_return "---\n"
        stale = File.join(dir, "plateau-handbook-11-10.yaml")
        File.write stale, "---\n"
        (1..10).each do |n|
          docid = Relaton::Bib::Docidentifier.new content: format("PLATEAU Handbook #%02d 第1.0版", n)
          fetcher.save_document Relaton::Plateau::ItemData.new(docidentifier: [docid])
        end
        expect(fetcher.prune_unwritten(min_ratio: 0.5)).to eq [stale]
        expect(Dir.children(dir).size).to eq 10
      end
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
