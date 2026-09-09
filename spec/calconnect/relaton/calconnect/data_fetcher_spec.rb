require "open3"
require "relaton/calconnect/data_fetcher"

RSpec.describe Relaton::Calconnect::DataFetcher do
  # relaton-data-calconnect's crawler.rb requires THIS file and nothing else,
  # so every constant #index touches has to be reachable from it alone. The
  # check runs in a clean subprocess because the suite loads
  # `relaton/calconnect` through spec_helper, which would define the constants
  # anyway and mask the failure. (The `spec/relaton/lazy_loading_spec.rb`
  # idiom; the invariant is the one the root CLAUDE.md states for processors.)
  it "builds its index from a bare require of data_fetcher" do
    script = <<~RUBY
      $LOAD_PATH.replace(#{$LOAD_PATH.inspect})
      require "relaton/calconnect/data_fetcher"
      fetcher = Relaton::Calconnect::DataFetcher.new "data", "yaml"
      io = fetcher.index.instance_variable_get(:@file_io)
      unless io.pubid_class == ::Pubid::Calconnect::Identifier
        abort "FAIL: pubid_class was \#{io.pubid_class.inspect}"
      end
      print "COLD_REQUIRE_PASS"
    RUBY
    out, = Open3.capture2e(RbConfig.ruby, "-e", script)
    expect(out).to include("COLD_REQUIRE_PASS")
  end

  context "instance methods" do
    subject { described_class.new "data", "yaml" }
    let(:files) { subject.instance_variable_get :@files }

    it "#etagfile" do
      expect(subject.etagfile).to eq "data/etag.txt"
    end

    context "#index" do
      it "is a pooled index type" do
        expect(subject.index).to be_instance_of Relaton::Index::Type
      end

      # Without `pubid_class:` here, FileIO#save calls `to_hash` only for
      # instances of it, so the crawl writes v1-shaped rows under a v2 name —
      # silently, and the consumer then rejects the whole index.
      it "is the pubid index-v2, on the producer side too" do
        expect(Relaton::Index).to receive(:find_or_create).with(
          :CC, file: "index-v2.yaml",
               pubid_class: ::Pubid::Calconnect::Identifier
        )
        subject.index
      end

      # It used to re-create the Type on every call (`@index =`, not `||=`),
      # which evicts the pooled entry a suite or a sibling call set up.
      it "is memoized" do
        expect(subject.index).to equal subject.index
      end
    end

    it "#fetch" do
      expect(subject).to receive(:etag).twice.and_return "old-etag"
      body = JSON.dump(
        "documents" => [
          { "id" => "cc-1" }, { "id" => "cc-2" }, { "id" => "cc-3" }
        ],
      )
      net_resp = { "etag" => "new-etag" }
      mech_resp = double "Mechanize response", code: "200", body: body, response: net_resp
      headers = {}
      agent = double "Mechanize agent", request_headers: headers
      expect(agent).to receive(:get).with(Relaton::Calconnect::DataFetcher::ENDPOINT).and_return mech_resp
      expect(subject).to receive(:agent).at_least(:once).and_return agent
      expect(subject).to receive(:parse_page).with(kind_of(Hash)).and_return(true).exactly(3).times
      expect(subject).to receive(:etag=).with("new-etag")
      expect(subject.index).to receive(:save)
      expect(subject).to receive(:report_errors)
      subject.fetch
      expect(headers).to eq("If-None-Match" => "old-etag")
    end

    it "#fetch returns early on 304 Not Modified" do
      expect(subject).to receive(:etag).at_least(:once).and_return "old-etag"
      mech_resp = double "Mechanize response", code: "304"
      agent = double "Mechanize agent", request_headers: {}
      expect(agent).to receive(:get).and_return mech_resp
      expect(subject).to receive(:agent).at_least(:once).and_return agent
      expect(subject).not_to receive(:parse_page)
      subject.fetch
    end

    context "#parse_page" do
      it do
        expect_any_instance_of(Relaton::Calconnect::Scraper).to receive(:parse_page).with(kind_of(Hash)).and_return :bib
        expect(subject).to receive(:write_doc).with("cc-1234", :bib)
        expect(subject.send(:parse_page, { "id" => "cc-1234" })).to be true
      end

      it "log error" do
        expect_any_instance_of(Relaton::Calconnect::Scraper).to receive(:parse_page).and_raise StandardError
        doc = { "id" => "cc-1234" }
        expect { subject.send(:parse_page, doc) }.to output(/Document: cc-1234/).to_stderr_from_any_process
      end
    end

    # The index key is a `Pubid::Calconnect::Identifier`, taken from the primary
    # docidentifier's own parsed pubid. No mutation and no `dup`: unlike ECMA,
    # the CalConnect index key IS the document's printed id, so there is no
    # index-only component to add.
    context "#index_id" do
      def item(*contents)
        docids = contents.map.with_index do |content, i|
          Relaton::Calconnect::Docidentifier.new content: content, primary: i.zero?
        end
        Relaton::Calconnect::ItemData.new docidentifier: docids
      end

      it "is the primary docidentifier's pubid" do
        id = subject.send(:index_id, item("CC/DIR 1234:2019"))
        expect(id).to be_a ::Pubid::Calconnect::Identifier
        expect(id.to_s).to eq "CC/DIR 1234:2019"
      end

      it "prefers the primary docidentifier over the first" do
        bib = item("CC/DIR 1234:2019", "CC/WD 9999:2001")
        bib.docidentifier[0].primary = false
        bib.docidentifier[1].primary = true
        expect(subject.send(:index_id, bib).to_s).to eq "CC/WD 9999:2001"
      end

      it "falls back to the first docidentifier when none is primary" do
        bib = item("CC/DIR 1234:2019")
        bib.docidentifier[0].primary = nil
        expect(subject.send(:index_id, bib).to_s).to eq "CC/DIR 1234:2019"
      end

      it "is nil when pubid rejects the docid" do
        bib = nil
        expect { bib = item("not an identifier") }.to output(/ERROR/).to_stderr_from_any_process
        expect(subject.send(:index_id, bib)).to be_nil
      end

      it "is nil when there is no docidentifier at all" do
        expect(subject.send(:index_id, Relaton::Calconnect::ItemData.new)).to be_nil
      end

      # The index holds this object, and `Docidentifier#remove_date!` mutates in
      # place, so a shared one would let a later most-recent-reference call
      # rewrite an already-indexed key.
      it "does not alias the record's own pubid" do
        bib = item("CC/DIR 1234:2019")
        id = subject.send(:index_id, bib)
        expect(id).not_to equal bib.docidentifier.first.pubid
        bib.docidentifier.first.remove_date!
        expect(id.to_s).to eq "CC/DIR 1234:2019"
      end
    end

    context "#write_doc" do
      let(:bib) do
        Relaton::Calconnect::ItemData.new(
          docidentifier: [
            Relaton::Calconnect::Docidentifier.new(content: "CC/DIR 1234:2019", primary: true),
          ],
        )
      end

      before do
        expect(subject).to receive(:serialize).with(bib).and_return :yaml
        expect(File).to receive(:write).with("data/cc-dir-1234.yaml", :yaml, encoding: "UTF-8")
      end

      it "keys the index by the primary docid's pubid, not the slug" do
        expect(subject.index).to receive(:add_or_update) do |id, file|
          expect(id).to be_a ::Pubid::Calconnect::Identifiers::Standard
          expect(id.to_s).to eq "CC/DIR 1234:2019"
          expect(file).to eq "data/cc-dir-1234.yaml"
        end
        subject.send(:write_doc, "cc-dir-1234", bib)
        expect(files).to include "data/cc-dir-1234.yaml"
      end

      it "warn if file exist" do
        allow(subject.index).to receive(:add_or_update)
        files << "data/cc-dir-1234.yaml"
        expect { subject.send(:write_doc, "cc-dir-1234", bib) }.to output(/exist/).to_stderr_from_any_process
      end
    end

    # `Relaton::Index` rejects the WHOLE index if one row fails to deserialize,
    # so an id pubid cannot rebuild is skipped rather than indexed unparsed. The
    # data file is still written — the document is unindexed, never lost — and
    # the failure is recorded in @errors, which report_errors logs and its
    # GhIssue channel turns into a GitHub issue at the end of the crawl.
    context "an unparseable primary id" do
      let(:bib) do
        bib = nil
        expect do
          bib = Relaton::Calconnect::ItemData.new(
            docidentifier: [
              Relaton::Calconnect::Docidentifier.new(content: "CC-DIR-1234", primary: true),
            ],
          )
        end.to output(/ERROR/).to_stderr_from_any_process
        bib
      end

      it "is recorded in @errors, skipped from the index, and still written" do
        expect(subject).to receive(:serialize).with(bib).and_return :yaml
        expect(File).to receive(:write).with("data/cc-dir-1234.yaml", :yaml, encoding: "UTF-8")
        expect(subject.index).not_to receive(:add_or_update)
        subject.send(:write_doc, "cc-dir-1234", bib)
        expect(subject.instance_variable_get(:@errors)["CC-DIR-1234"])
          .to eq "Unparseable primary id `CC-DIR-1234` was not indexed (data/cc-dir-1234.yaml)"
      end

      it "reaches report_errors, which opens the GitHub issue" do
        allow(subject).to receive(:serialize).and_return :yaml
        allow(File).to receive(:write)
        subject.send(:write_doc, "cc-dir-1234", bib)
        expect(subject).to receive(:log_error)
          .with("Unparseable primary id `CC-DIR-1234` was not indexed (data/cc-dir-1234.yaml)")
        subject.report_errors
      end
    end

    context "serialize" do
      let(:bib) { Relaton::Calconnect::ItemData.new(docnumber: "CC/DIR 10005:2019") }

      it "#to_yaml" do
        expect(subject.send(:to_yaml, bib)).to include "docnumber: CC/DIR 10005:2019"
      end

      context "xml" do
        before { subject.instance_variable_set :@ext, "xml" }

        it "#to_xml" do
          subject.instance_variable_set :@format, "xml"
          expect(subject.send(:to_xml, bib)).to include "<bibdata"
        end

        it "#to_bibxml" do
          subject.instance_variable_set :@format, "bibxml"
          expect(subject.send(:to_bibxml, bib)).to include 'anchor="CC/DIR 10005:2019"'
        end
      end
    end

    context "#etag" do
      it "file exist" do
        expect(File).to receive(:exist?).with("data/etag.txt").and_return true
        expect(File).to receive(:read).with("data/etag.txt", encoding: "UTF-8").and_return "1234"
        expect(subject.send(:etag)).to eq "1234"
      end

      it "file doesn't exist" do
        expect(File).to receive(:exist?).with("data/etag.txt").and_return false
        expect(subject.send(:etag)).to be_nil
      end
    end

    it "#etag=" do
      expect(File).to receive(:write).with("data/etag.txt", "1234", encoding: "UTF-8")
      subject.send(:etag=, "1234")
    end

    # The other branch of `Core::DataFetcher#report_errors`: a boolean value
    # means "this field failed for every record" and its message is derived from
    # the key, where a String value IS the message (covered above by the
    # unparseable-id example). A false value is not reported at all.
    #
    # This used to stub `report_errors` on the subject and then call the stub,
    # so it passed whatever the method did.
    it "#report_errors derives a message from the key for a boolean error" do
      errors = subject.instance_variable_get(:@errors)
      errors[:title] = false
      errors[:date] = true
      expect(subject).to receive(:log_error).with("Failed to fetch date")
      expect(subject).not_to receive(:log_error).with(/title/)
      subject.report_errors
    end
  end
end
