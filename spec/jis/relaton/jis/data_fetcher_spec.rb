# encoding: UTF-8
# frozen_string_literal: true

require "relaton/jis/data_fetcher"

describe Relaton::Jis::DataFetcher do # rubocop:disable Metrics/BlockLength
  subject { described_class.new "data", "bibxml" }
  let(:next_url) do
    "https://webdesk.jsa.or.jp/books/W11M0070/getAddList"
  end
  let(:next_body) { { search_type: "JIS", offset: 100 } }
  let(:bib) do
    docid = Relaton::Jis::Docidentifier.new(
      content: "JIS A 1301:1994", type: "JIS", primary: true,
    )
    Relaton::Bib::ItemData.new docidentifier: [docid]
  end

  context "initialize" do
    it do
      expect(subject.instance_variable_get(:@output)).to eq "data"
    end
    it do
      expect(subject.instance_variable_get(:@format)).to eq "bibxml"
    end
    it do
      expect(subject.instance_variable_get(:@ext)).to eq "xml"
    end
    it do
      ivar = subject.instance_variable_get(:@files)
      expect(ivar).to be_instance_of Set
    end
    it do
      ivar = subject.instance_variable_get(:@errors)
      expect(ivar).to be_instance_of Hash
    end
    it do
      ivar = subject.instance_variable_get(:@queue)
      expect(ivar).to be_instance_of SizedQueue
    end
    it do
      ivar = subject.instance_variable_get(:@mutex)
      expect(ivar).to be_instance_of Mutex
    end
    it do
      ivar = subject.instance_variable_get(:@threads)
      expect(ivar).to be_instance_of Array
    end
  end

  context ".fetch" do
    before { expect(subject).to receive(:fetch) }

    it "with default values" do
      expect(FileUtils).to receive(:mkdir_p).with("data")
      expect(described_class).to receive(:new)
        .with("data", "yaml").and_return subject
      described_class.fetch
    end

    it "with custom values" do
      expect(FileUtils).to receive(:mkdir_p).with("dir")
      expect(described_class).to receive(:new)
        .with("dir", "xml").and_return subject
      described_class.fetch output: "dir", format: "xml"
    end
  end

  context "instance methods" do # rubocop:disable Metrics/BlockLength
    context "#fetch" do
      let(:url1) do
        "https://webdesk.jsa.or.jp/books/W11M0270/index"
      end
      let(:url2) do
        "https://webdesk.jsa.or.jp/books/W11M0070/index"
      end
      let(:body) do
        { record: 0, dantai: "JIS", searchtype2: 1,
          status_1: 1, status_2: 2 } # rubocop:disable Naming/VariableNumber
      end
      let(:resp) do
        Nokogiri::HTML(<<~HTML)
          <body>
            <form id="search_by_keyword" name="search_by_keyword" method="post" action="https://webdesk.jsa.or.jp/books/W11M0080/index">
              <input type="hidden" name="offset" id="offset" value="50">
            </form>
          </body>
        HTML
      end

      it "no results" do
        resp_body = { "status" => false }.to_json
        expect(subject.agent).to receive(:post)
          .with(url1, body).and_return double(body: resp_body)
        expect(subject.agent).not_to receive(:get)
        subject.fetch
      end

      it "with results" do
        resp_body = { "status" => true }.to_json
        expect(subject.agent).to receive(:post)
          .with(url1, body).and_return double(body: resp_body)
        expect(subject.agent).to receive(:get)
          .with(url2).and_return resp
        expect(subject).to receive(:parse_page).with(resp)
        expect(subject.index).to receive(:save)
        expect(subject.index_v2).to receive(:save)
        subject.fetch
      end
    end

    context "#parse_page" do
      let(:page1) do
        path = "fixtures/page1.html"
        Nokogiri::HTML(File.read(path, encoding: "UTF-8"))
      end
      let(:page2) do
        path = "fixtures/page2.html"
        Nokogiri::HTML(File.read(path, encoding: "UTF-8"))
      end
      before do
        expect(subject).to receive(:fetch_doc)
          .with(/\/index\/\?bunsyo_id=\w+/)
          .exactly(50).times
      end

      it "first page" do
        expect(subject).to receive(:get_next_page).with(50)
        subject.parse_page page1
      end

      it "next page" do
        subject.instance_variable_set :@count, 110
        expect(subject).to receive(:get_next_page).with(100)
        subject.parse_page page2
      end

      it "no more pages" do
        expect(subject).not_to receive(:get_next_page)
        subject.parse_page page2
      end
    end

    context "#get_next_page" do
      it "success" do
        expect(subject).to receive(:initial_post)
          .and_return true
        expect(subject.agent).to receive(:post)
          .with(next_url, next_body).and_return :next_page
        expect(subject.get_next_page(100)).to eq :next_page
      end

      it "initial failed" do
        expect(subject).to receive(:initial_post)
          .and_return false
        expect(subject.agent).not_to receive(:post)
        expect(subject.get_next_page(100)).to be_nil
      end

      it "post failed" do
        allow(subject).to receive(:sleep)
        expect(subject).to receive(:initial_post)
          .and_return(true).exactly(5).times
        expect(subject.agent).to receive(:post)
          .with(next_url, next_body)
          .and_raise(StandardError).exactly(5).times
        expect do
          expect(subject.get_next_page(100)).to be_nil
        end.to output(/WARN: StandardError/)
          .to_stderr_from_any_process
      end
    end

    context "#fetch_doc" do
      let(:scraper) { double "scraper" }
      before do
        allow(Relaton::Jis::Scraper).to receive(:new)
          .with("url", kind_of(Hash)).and_return scraper
      end

      it "success" do
        expect(scraper).to receive(:fetch).and_return :bib
        expect(subject).to receive(:save_doc).with(:bib, "url")
        subject.fetch_doc "url"
      end

      it "failed" do
        expect(subject).to receive(:sleep).exactly(4).times
        expect(scraper).to receive(:fetch)
          .and_raise(StandardError).exactly(5).times
        expect(subject).not_to receive(:save_doc)
        expect { subject.fetch_doc "url" }
          .to output(/WARN: StandardError/)
          .to_stderr_from_any_process
      end
    end

    context "#save_doc" do
      let(:id) { "JIS A 1301:1994" }
      let(:file) { "data/jis-a-1301-1994.xml" }

      it "file exists" do
        subject.instance_variable_get(:@files) << file
        expect { subject.save_doc bib, "url" }.to output(
          /File #{Regexp.escape(file)} already exists/,
        ).to_stderr_from_any_process
      end

      it "file does not exist" do
        allow(subject).to receive(:serialize)
          .with(bib).and_return "serialized"
        expect(File).to receive(:write)
          .with(file, "serialized", encoding: "UTF-8")
        expect(subject.index).to receive(:add_or_update)
          .with(id, file)
        subject.save_doc bib, "url"
      end
    end

    context "#serialize" do
      it "yaml" do
        subject.instance_variable_set :@format, "yaml"
        expect(Relaton::Jis::Item).to receive(:to_yaml)
          .with(bib).and_return "yaml_output"
        expect(subject.serialize(bib)).to eq "yaml_output"
      end

      it "xml" do
        subject.instance_variable_set :@format, "xml"
        expect(Relaton::Jis::Bibdata).to receive(:to_xml)
          .with(bib).and_return "xml_output"
        expect(subject.serialize(bib)).to eq "xml_output"
      end

      it "bibxml" do
        expect(bib).to receive(:to_rfcxml)
          .and_return "bibxml_output"
        expect(subject.serialize(bib)).to eq "bibxml_output"
      end
    end
  end
end
