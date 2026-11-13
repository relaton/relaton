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

  # The relaton-data-jis crawler runs `fetch(prune: true)`. A crawl that
  # raises must stop before the prune deletes anything.
  context ".fetch in prune mode" do
    it "does not prune when the crawl raises" do
      allow(FileUtils).to receive(:mkdir_p)
      allow(described_class).to receive(:new).and_return subject
      expect(subject).to receive(:fetch)
        .and_raise Relaton::Jis::Error, "Webdesk list JIS stopped"
      expect(subject).not_to receive(:prune_unwritten)
      expect { described_class.fetch prune: true }
        .to raise_error(Relaton::Jis::Error, /stopped/)
        .and output.to_stdout
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

      let(:jwes_url) do
        "https://webdesk.jsa.or.jp/books/W11S0260/getSearchAllListByLink" \
          "?dantai_cd=JWES&display=KOKUNAI"
      end
      let(:jwes_page) do
        Nokogiri::HTML("<script>var count = 104;</script>")
      end
      let(:index) { double("index") }

      before do
        allow(Relaton::Index).to receive(:find_or_create).and_return index
      end

      # relaton-data-jis deletes data/ before a crawl and publishes what the
      # crawl wrote, so a list that does not open fails the whole crawl.
      it "raises when the JIS search finds nothing" do
        resp_body = { "status" => false }.to_json
        expect(subject.agent).to receive(:post)
          .with(url1, body).and_return double(body: resp_body)
        expect(subject.agent).not_to receive(:get)
        expect(index).not_to receive(:save)
        expect { subject.fetch }.to raise_error(Relaton::Jis::Error, /JIS/)
          .and output(/No results found for JIS/).to_stderr_from_any_process
        expect(subject.instance_variable_get(:@threads)).to all(satisfy { |t| !t.alive? })
      end

      it "reads the JIS search, then the JWES list" do
        resp_body = { "status" => true }.to_json
        expect(subject.agent).to receive(:post)
          .with(url1, body).ordered.and_return double(body: resp_body)
        expect(subject.agent).to receive(:get).with(url2).ordered.and_return resp
        expect(subject.agent).to receive(:get).with(jwes_url).ordered.and_return jwes_page
        expect(subject.agent).to receive(:get).with(url2).ordered.and_return resp
        expect(subject).to receive(:parse_page).with(resp).twice
        expect(index).to receive(:save).once
        subject.fetch
      end

      it "raises when the JWES list is empty, after the JIS list" do
        resp_body = { "status" => true }.to_json
        allow(subject.agent).to receive(:post)
          .with(url1, body).and_return double(body: resp_body)
        expect(subject.agent).to receive(:get).with(url2).once.and_return resp
        expect(subject.agent).to receive(:get).with(jwes_url)
          .and_return Nokogiri::HTML("<script>var count = 0;</script>")
        expect(subject).to receive(:parse_page).with(resp).once
        expect(index).not_to receive(:save)
        expect { subject.fetch }.to raise_error(Relaton::Jis::Error, /JWES/)
          .and output(/No results found for JWES/).to_stderr_from_any_process
      end

      it "ends the threads when a list page raises" do
        expect(subject).to receive(:initial_post).and_return true
        expect(subject.agent).to receive(:get).with(url2).and_raise NoMethodError
        expect(index).not_to receive(:save)
        expect { subject.fetch }.to raise_error NoMethodError
        expect(subject.instance_variable_get(:@threads)).to all(satisfy { |t| !t.alive? })
      end

      # relaton-data-jis rebuilds the legacy index-v1 from data/ in its own
      # crawler, so a crawl writes index-v2 and nothing else.
      it "opens and saves one index only" do
        expect(Relaton::Index).to receive(:find_or_create).once.and_return index
        expect(index).to receive(:save).once
        expect(subject).to receive(:initial_post).twice.and_return true
        expect(subject.agent).to receive(:get).with(url2).twice.and_return resp
        expect(subject).to receive(:parse_page).with(resp).twice
        subject.fetch
      end
    end

    context "#initial_post" do
      let(:jwes_url) do
        "https://webdesk.jsa.or.jp/books/W11S0260/getSearchAllListByLink" \
          "?dantai_cd=JWES&display=KOKUNAI"
      end

      it "opens the JWES list by its group link" do
        subject.instance_variable_set :@list, "JWES"
        expect(subject.agent).to receive(:get).with(jwes_url)
          .and_return Nokogiri::HTML("<script>var count = 104;</script>")
        expect(subject.initial_post).to be true
      end

      it "does not open a list again within 10 minutes" do
        subject.instance_variable_set :@list, "JWES"
        expect(subject.agent).to receive(:get).with(jwes_url).once
          .and_return Nokogiri::HTML("<script>var count = 104;</script>")
        2.times { subject.initial_post }
      end

      # The session holds one list: a refresh during the JWES list must not
      # switch the session back to the JIS search.
      it "opens the current list again after 10 minutes" do
        subject.instance_variable_set :@list, "JWES"
        subject.instance_variable_set :@initial_time, Time.now - 601
        expect(subject.agent).not_to receive(:post)
        expect(subject.agent).to receive(:get).with(jwes_url)
          .and_return Nokogiri::HTML("<script>var count = 104;</script>")
        expect(subject.initial_post).to be true
      end
    end

    context "#index" do
      it "is the pubid index-v2" do
        index = double("index")
        expect(Relaton::Index).to receive(:find_or_create).with(
          :jis, file: "index-v2.yaml", pubid_class: Pubid::Jis::Identifier
        ).and_return index
        expect(subject.index).to be index
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
        subject.end_threads_and_wait # #fetch ends the threads once
      end

      it "next page" do
        subject.instance_variable_set :@count, 110
        expect(subject).to receive(:get_next_page).with(100)
        subject.parse_page page2
        subject.end_threads_and_wait # #fetch ends the threads once
      end

      it "no more pages" do
        expect(subject).not_to receive(:get_next_page)
        subject.parse_page page2
        subject.end_threads_and_wait # #fetch ends the threads once
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

      # A list that stops part way must stop the crawl: in prune mode the
      # unread documents would otherwise be deleted.
      it "raises when the list does not open again" do
        subject.instance_variable_set :@list, "JWES"
        expect(subject).to receive(:initial_post)
          .and_return false
        expect(subject.agent).not_to receive(:post)
        expect { subject.get_next_page(100) }
          .to raise_error(Relaton::Jis::Error, /JWES.*offset 100/)
      end

      it "raises after 5 failed tries" do
        subject.instance_variable_set :@list, "JIS"
        allow(subject).to receive(:sleep)
        expect(subject).to receive(:initial_post)
          .and_return(true).exactly(5).times
        expect(subject.agent).to receive(:post)
          .with(next_url, next_body)
          .and_raise(StandardError, "timeout").exactly(5).times
        expect { subject.get_next_page(100) }
          .to raise_error(Relaton::Jis::Error, /JIS.*offset 100.*timeout/)
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
        expect(subject.instance_variable_get(:@failed_docs)).to eq ["url"]
      end
    end

    # The crawler runs in prune mode: prune deletes the files a run did not
    # write, so a run deletes nothing when a document did not fetch.
    context "#prune_unwritten" do
      let(:dir) { Dir.mktmpdir "relaton-jis-prune" }
      let(:kept) { File.join dir, "jis-a-1301-1994.xml" }
      let(:stale) { File.join dir, "jis-a-9999-1990.xml" }
      subject { described_class.new dir, "bibxml" }

      before do
        allow(Relaton::Index).to receive(:find_or_create).and_return double("index", add_or_update: nil)
        allow(subject).to receive(:serialize).and_return "serialized"
        File.write stale, "old"
        subject.save_doc bib, "url"
      end

      after { FileUtils.rm_rf dir }

      it "deletes a file the run did not write" do
        expect(subject.prune_unwritten(min_ratio: 0)).to eq [stale]
        expect(File.exist?(kept)).to be true
      end

      it "deletes nothing after a document did not fetch" do
        subject.instance_variable_get(:@failed_docs) << "url2"
        expect { expect(subject.prune_unwritten(min_ratio: 0)).to eq [] }
          .to output(/prune skipped: 1 document\(s\) did not fetch/)
          .to_stderr_from_any_process
        expect(File.exist?(stale)).to be true
      end
    end

    context "#save_doc" do
      let(:id) { "JIS A 1301:1994" }
      let(:file) { "data/jis-a-1301-1994.xml" }
      # A double, so the example does not replace the suite's pooled :jis
      # fixture index (spec/jis/support/webmock.rb).
      let(:index) { double("index") }
      before do
        allow(Relaton::Index).to receive(:find_or_create).and_return index
      end

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
        expect(index).to receive(:add_or_update)
          .with(kind_of(Pubid::Jis::Identifier), file)
        expect(index).not_to receive(:add_or_update).with(id, anything)
        subject.save_doc bib, "url"
      end

      # The document is still written to data/, where relaton-data-jis picks
      # it up for index-v1, but index-v2 only takes a parsed pubid.
      it "writes but does not index an id pubid cannot parse" do
        allow(subject).to receive(:serialize)
          .with(bib).and_return "serialized"
        expect(Pubid::Jis::Identifier).to receive(:parse).with(id)
          .and_raise StandardError, "unparseable"
        expect(File).to receive(:write)
          .with(file, "serialized", encoding: "UTF-8")
        expect(index).not_to receive(:add_or_update)
        expect { subject.save_doc bib, "url" }.to output(
          /Failed to parse `#{Regexp.escape(id)}` with pubid: unparseable/,
        ).to_stderr_from_any_process
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
