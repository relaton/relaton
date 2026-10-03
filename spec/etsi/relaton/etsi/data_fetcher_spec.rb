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

    it "#fetch single page" do
      agent = double("mechanize")
      allow(Mechanize).to receive(:new).and_return agent
      body = '[{"total_count":"1","wki_id":"73740","TITLE":"T",' \
             '"ETSI_DELIVERABLE":"ETSI EN 1 V1.0.0 (2024-01)",' \
             '"STATUS_CODE":"12","ACTION_TYPE":"PU",' \
             '"EDSpathname":"x/","EDSPDFfilename":"y.pdf",' \
             '"Scope":"S","TB":"WG","Keywords":"k"}]'
      expect(agent).to receive(:get).with(kind_of(String)).and_return double("page", body: body)
      data_parser = double "data_parser"
      expect(data_parser).to receive(:parse).and_return :bibitem
      expect(Relaton::Etsi::DataParser).to receive(:new).with(kind_of(Hash), kind_of(Hash)).and_return data_parser
      expect(subject).to receive(:save).with(:bibitem)
      expect(subject.index).to receive(:save)
      subject.fetch
    end

    it "#fetch paginates by total_count" do
      agent = double("mechanize")
      allow(Mechanize).to receive(:new).and_return agent
      record = '{"total_count":"75","wki_id":"1","ETSI_DELIVERABLE":"ETSI EN 1 V1.0.0 (2024-01)",' \
               '"STATUS_CODE":"12","ACTION_TYPE":"PU","EDSpathname":"","EDSPDFfilename":"",' \
               '"TITLE":"T","Scope":"S","TB":"WG","Keywords":"k"}'
      page1 = "[#{Array.new(50, record).join(',')}]"
      page2 = "[#{Array.new(25, record).join(',')}]"
      expect(agent).to receive(:get).with(kind_of(String)).and_return(
        double("page1", body: page1),
        double("page2", body: page2),
      )
      allow(Relaton::Etsi::DataParser).to receive(:new).and_return double("data_parser", parse: :bibitem)
      allow(subject).to receive(:save)
      expect(subject.index).to receive(:save)
      subject.fetch
      expect(subject).to have_received(:save).exactly(75).times
    end

    context "a page whose body is not a JSON array" do
      # ETSI's data.php sometimes answers with PHP's `Array` text in place of
      # JSON (relaton-data-etsi crawl 36761804954). relaton-data-etsi deletes
      # data/ before the crawl and commits the result, so a skipped page would
      # unpublish its documents: a bad page is retried, then deferred, then
      # fails the crawl — it is never skipped.
      let(:agent) { double("mechanize") }

      def record(total, deliverable = "ETSI EN 1 V1.0.0 (2024-01)")
        { total_count: total.to_s, wki_id: "1", ETSI_DELIVERABLE: deliverable, STATUS_CODE: "12",
          ACTION_TYPE: "PU", EDSpathname: "", EDSPDFfilename: "", TITLE: "T", Scope: "S",
          TB: "WG", Keywords: "k" }
      end

      def page(total, size, deliverable = "ETSI EN 1 V1.0.0 (2024-01)")
        double("page", body: Array.new(size) { record(total, deliverable) }.to_json)
      end

      let(:bad) { double("bad page", body: "Array\n(\n    [0] => x\n)\n") }

      # Answers by page number from a queue per page.
      def serve(pages)
        allow(agent).to receive(:get) do |url|
          num = url[/[?&]page=(\d+)/, 1].to_i
          queue = pages.fetch(num)
          queue.size > 1 ? queue.shift : queue.first
        end
      end

      before do
        allow(Mechanize).to receive(:new).and_return agent
        allow(subject).to receive(:sleep)
        allow(Relaton::Etsi::Util).to receive(:info)
        allow(Relaton::Etsi::DataParser).to receive(:new) do |hash, _|
          double("data_parser", parse: hash["ETSI deliverable"])
        end
        allow(subject).to receive(:save)
      end

      it "retries the page and processes it" do
        serve 1 => [bad, page(1, 1)]
        expect(subject.index).to receive(:save)
        subject.fetch
        expect(subject).to have_received(:save).once
        expect(Relaton::Etsi::Util).to have_received(:info).with(/page 1 .*"Array/)
      end

      it "retries a JSON body that is not an Array" do
        serve 1 => [double("page", body: "{}"), page(1, 1)]
        expect(subject.index).to receive(:save)
        subject.fetch
        expect(subject).to have_received(:save).once
      end

      it "defers a page that stays bad and fetches it after the last page" do
        p2 = page(110, 50, "ETSI EN 2 V1.0.0 (2024-01)")
        p3 = page(110, 10, "ETSI EN 3 V1.0.0 (2024-01)")
        serve 1 => [page(110, 50)], 2 => [bad, bad, bad, bad, p2], 3 => [p3]
        saved = []
        allow(subject).to receive(:save) { |id| saved << id }
        expect(subject.index).to receive(:save)
        expect { subject.fetch }.to output(/WARN: ETSI page 2 .*after the last page/).to_stderr_from_any_process
        expect(saved.size).to eq 110
        expect(saved.chunk_while { |a, b| a == b }.map(&:first)).to eq [
          "ETSI EN 1 V1.0.0 (2024-01)", "ETSI EN 3 V1.0.0 (2024-01)", "ETSI EN 2 V1.0.0 (2024-01)"
        ]
      end

      it "fails the crawl when the deferred page is still bad" do
        serve 1 => [page(110, 50)], 2 => [bad], 3 => [page(110, 10)]
        expect(subject.index).not_to receive(:save)
        expect do
          expect { subject.fetch }.to raise_error(
            Relaton::Etsi::DataFetcher::BadPage, /page 2 .*"Array\\n\(/
          )
        end.to output(/WARN: ETSI page 2 /).to_stderr_from_any_process
        expect(subject).to have_received(:save).exactly(60).times
      end

      it "waits DEFERRED_DELAY before it fetches a deferred page" do
        serve 1 => [page(110, 50)], 2 => [bad, bad, bad, bad, page(110, 50)], 3 => [page(110, 10)]
        expect(subject.index).to receive(:save)
        expect { subject.fetch }.to output(/WARN/).to_stderr_from_any_process
        expect(subject).to have_received(:sleep).with(60)
      end

      it "reads one page past a deferred last page, and no further" do
        # Page 3 is past the end and bad: it does not extend the range, so page
        # 4 is never read. Its re-fetch answers `[]`, which past the range is
        # the normal end of the result set.
        serve 1 => [page(100, 50)], 2 => [bad, bad, bad, bad, page(100, 50)],
              3 => [bad, bad, bad, bad, page(100, 0)], 4 => [bad]
        expect(subject.index).to receive(:save)
        expect { subject.fetch }.to output(/WARN: ETSI page 3 /).to_stderr_from_any_process
        expect(agent).not_to have_received(:get).with(/[?&]page=4&/)
        expect(subject).to have_received(:save).exactly(100).times
      end

      it "fails the crawl when the pages stay full past total_count" do
        # A server that ignores `page=` past the end must not loop forever.
        # Page 1 is full, so the range is 2 pages; pages 3..12 are the extra ones.
        allow(agent).to receive(:get).and_return page(50, 50)
        expect(subject.index).not_to receive(:save)
        expect { subject.fetch }.to raise_error(
          Relaton::Etsi::DataFetcher::BadPage, /page 13 is still full 10 pages past/
        )
        expect(subject).to have_received(:save).exactly(600).times
      end

      it "fails the crawl when a deferred page comes back empty" do
        serve 1 => [page(110, 50)], 2 => [bad, bad, bad, bad, page(110, 0)], 3 => [page(110, 10)]
        expect(subject.index).not_to receive(:save)
        expect do
          expect { subject.fetch }.to raise_error(
            Relaton::Etsi::DataFetcher::BadPage, /page 2 is empty on the re-fetch/
          )
        end.to output(/WARN/).to_stderr_from_any_process
      end

      it "reads page 2 when page 1 is full and total_count is missing" do
        serve 1 => [page(0, 50)], 2 => [page(0, 3)]
        expect(subject.index).to receive(:save)
        subject.fetch
        expect(subject).to have_received(:save).exactly(53).times
      end

      it "fails the crawl when the first page stays bad" do
        serve 1 => [bad]
        expect(subject.index).not_to receive(:save)
        expect { subject.fetch }.to raise_error(Relaton::Etsi::DataFetcher::BadPage, /page 1 /)
      end
    end

    it "#fetch reads past total_count while the pages stay full" do
      # A document published during the crawl shifts the later pages by one,
      # so the last record lands on a page past page 1's total_count.
      agent = double("mechanize")
      allow(Mechanize).to receive(:new).and_return agent
      record = '{"total_count":"100","wki_id":"1","ETSI_DELIVERABLE":"ETSI EN 1 V1.0.0 (2024-01)",' \
               '"STATUS_CODE":"12","ACTION_TYPE":"PU","EDSpathname":"","EDSPDFfilename":"",' \
               '"TITLE":"T","Scope":"S","TB":"WG","Keywords":"k"}'
      full = "[#{Array.new(50, record).join(',')}]"
      expect(agent).to receive(:get).with(kind_of(String)).and_return(
        double("page1", body: full), double("page2", body: full), double("page3", body: "[#{record}]"),
      )
      allow(Relaton::Etsi::DataParser).to receive(:new).and_return double("data_parser", parse: :bibitem)
      allow(subject).to receive(:save)
      expect(subject.index).to receive(:save)
      subject.fetch
      expect(subject).to have_received(:save).exactly(101).times
    end

    it "#fetch reads past a full first page" do
      agent = double("mechanize")
      allow(Mechanize).to receive(:new).and_return agent
      record = '{"total_count":"50","wki_id":"1","ETSI_DELIVERABLE":"ETSI EN 1 V1.0.0 (2024-01)",' \
               '"STATUS_CODE":"12","ACTION_TYPE":"PU","EDSpathname":"","EDSPDFfilename":"",' \
               '"TITLE":"T","Scope":"S","TB":"WG","Keywords":"k"}'
      expect(agent).to receive(:get).with(kind_of(String)).and_return(
        double("page1", body: "[#{Array.new(50, record).join(',')}]"), double("page2", body: "[#{record}]"),
      )
      allow(Relaton::Etsi::DataParser).to receive(:new).and_return double("data_parser", parse: :bibitem)
      allow(subject).to receive(:save)
      expect(subject.index).to receive(:save)
      subject.fetch
      expect(subject).to have_received(:save).exactly(51).times
    end

    it "#fetch_page asks ETSI for superseded editions" do
      # `version=1` keeps the superseded editions of a document in the result
      # set. See lib/relaton/etsi/data_fetcher.rb SOURCEURL.
      agent = double("mechanize")
      allow(Mechanize).to receive(:new).and_return agent
      expect(agent).to receive(:get).with(a_string_matching(/page=3&.+&version=1&/))
        .and_return double("page", body: "[]")
      subject.fetch_page 3
    end

    context "#derive_status" do
      it "Withdrawn" do
        expect(subject.send(:derive_status, "ACTION_TYPE" => "WD", "STATUS_CODE" => "12")).to eq "Withdrawn"
      end

      it "On Approval" do
        expect(subject.send(:derive_status, "ACTION_TYPE" => "PU", "STATUS_CODE" => "5")).to eq "On Approval"
      end

      it "Historical" do
        expect(subject.send(:derive_status, "ACTION_TYPE" => "PU", "STATUS_CODE" => "13")).to eq "Historical"
      end

      it "Published" do
        expect(subject.send(:derive_status, "ACTION_TYPE" => "PU", "STATUS_CODE" => "12")).to eq "Published"
      end
    end

    it "#normalize maps JSON keys to CSV-compatible keys" do
      record = {
        "ETSI_DELIVERABLE" => "ETSI EN 1 V1.0.0 (2024-01)",
        "TITLE" => "Title",
        "wki_id" => "73740",
        "EDSpathname" => "etsi_gr/ZSM/001/",
        "EDSPDFfilename" => "doc.pdf",
        "STATUS_CODE" => "12", "ACTION_TYPE" => "PU",
        "Keywords" => "k1,k2", "TB" => "ZSM", "Scope" => "S"
      }
      hash = subject.send(:normalize, record)
      expect(hash["ETSI deliverable"]).to eq "ETSI EN 1 V1.0.0 (2024-01)"
      expect(hash["title"]).to eq "Title"
      expect(hash["Details link"]).to eq "https://webapp.etsi.org/workprogram/Report_WorkItem.asp?WKI_ID=73740"
      expect(hash["PDF link"]).to eq "https://www.etsi.org/deliver/etsi_gr/ZSM/001/doc.pdf"
      expect(hash["Status"]).to eq "Published"
      expect(hash["Keywords"]).to eq "k1,k2"
      expect(hash["Technical body"]).to eq "ZSM"
      expect(hash["Scope"]).to eq "S"
    end

    it "#save indexes the parsed pubid object" do
      did = Relaton::Bib::Docidentifier.new type: "ETSI", content: "ETSI EN 300 175-1 V2.1.1 (2001-08)"
      bib = Relaton::Bib::ItemData.new docidentifier: [did]
      file = "dir/etsi-en-300-175-1-v2-1-1-2001-08.xml"
      expect(File).to receive(:write).with(file, kind_of(String), encoding: "UTF-8")
      expect(subject.index).to receive(:add_or_update)
        .with(kind_of(::Pubid::Etsi::Identifier), file)
      subject.save bib
    end

    it "#save keeps every edition of one document" do
      # The `version=1` query returns each edition of a document. The version is
      # part of the docid, so the editions must not collapse to one file or to
      # one index row.
      ids = ["ETSI EN 319 142-1 V1.1.1 (2016-04)",
             "ETSI EN 319 142-1 V1.2.1 (2024-01)",
             "ETSI EN 319 142-1 V1.3.0 (2026-08)"]
      files = []
      allow(File).to receive(:write) { |file, *| files << file }
      indexed = []
      allow(subject.index).to receive(:add_or_update) { |pid, file| indexed << [pid.to_s, file] }

      ids.each do |id|
        did = Relaton::Bib::Docidentifier.new type: "ETSI", content: id
        subject.save Relaton::Bib::ItemData.new(docidentifier: [did])
      end

      expect(files.uniq.size).to eq 3
      expect(indexed.map(&:first).uniq.size).to eq 3
      expect(indexed.map(&:last)).to eq files
    end

    it "#save skips an id pubid can't parse (no write, no index entry)" do
      # "ETSI A/12 ed.1 (2019-10)" has no valid ETSI type token, so it must be
      # skipped whole rather than corrupt the index.
      expect(File).not_to receive(:write)
      expect(subject.index).not_to receive(:add_or_update)
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
