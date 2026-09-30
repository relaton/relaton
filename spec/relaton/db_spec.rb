RSpec.describe Relaton::Db do
  before(:each) do |example|
    # Relaton::Db.instance_variable_set :@configuration, nil
    FileUtils.rm_rf %w[testcache testcache2]

    if example.metadata[:vcr]
      # Force to download index file
      require "relaton/index"
      allow_any_instance_of(Relaton::Index::Type)
        .to receive(:actual?).and_return(false)
      allow_any_instance_of(Relaton::Index::FileIO)
        .to receive(:check_file).and_return(nil)
    end
  end

  subject { Relaton::Db.new nil, nil }

  context "instance methods" do
    context "#search_edition_year" do
      it "create bibitem from XML content" do
        processor = Relaton::Db::Registry.instance[:relaton_iso]
        xml = '<bibdata><docidentifier type="ISO" primary="true">' \
              "ISO 123</docidentifier></bibdata>"
        item = subject.send :search_edition_year, processor, xml, nil, nil
        expect(item).to be_instance_of Relaton::Iso::ItemData
      end
    end

    context "#new_bib_entry" do
      let(:db) { double "db" }
      before do
        expect(db).to receive(:[]).with("ISO(ISO 123)").and_return "not_found"
      end

      it "warn if cached entry is not_found" do
        expect do
          expect(subject).to_not receive(:fetch_entry)
          entry = subject.send :new_bib_entry, "ISO 123", nil, {},
                               :relaton_iso, db: db, id: "ISO(ISO 123)"
          expect(entry).to be_nil
        end.to output(
          "[relaton-db] INFO: (ISO 123) not found in cache, " \
          "if you wish to ignore cache please use " \
          "`no-cache` option.\n",
        ).to_stderr_from_any_process
      end

      it "ignore cache" do
        expect(subject).to receive(:fetch_entry).with(
          "ISO 123", nil, { no_cache: true }, :relaton_iso,
          db: db, id: "ISO(ISO 123)"
        ).and_return :entry
        entry = subject.send(
          :new_bib_entry, "ISO 123", nil, { no_cache: true },
          :relaton_iso, db: db, id: "ISO(ISO 123)"
        )
        expect(entry).to be :entry
      end
    end

    context "#combine_doc" do
      it "retrun nil for BIPM documents" do
        code = double "code"
        expect(code).not_to receive(:split)
        expect(subject.send(:combine_doc, code, nil, {},
                            :relaton_bipm)).to be_nil
      end
    end

    context "#fetch_entry" do
      let(:db_cache) { double "db_cache" }
      let(:bib) do
        docid = Relaton::Bib::Docidentifier.new(content: "ISO 123:2020",
                                                type: "ISO", primary: true)
        Relaton::Iso::ItemData.new docidentifier: [docid]
      end

      before do
        expect(subject).to receive(:net_retry).with(
          "ISO 123", nil, kind_of(Hash),
          kind_of(Relaton::Iso::Processor), 1
        ).and_return bib
      end

      it "caches the document under the query and its own key" do
        expect(db_cache).to receive(:[]).with(:key).and_return nil
        expect(db_cache).to receive(:store) do |key, entry, item_key:|
          expect(key).to be :key
          expect(entry).to include "ISO 123:2020"
          expect(item_key.to_s).to eq "ISO 123:2020"
        end
        entry = subject.send :fetch_entry, "ISO 123", nil, {}, :relaton_iso,
                             db: db_cache, id: :key
        expect(entry).to include "ISO 123:2020"
      end

      it "DbCache is undefined" do
        entry = subject.send :fetch_entry, "ISO 123", nil, {}, :relaton_iso
        expect(entry).to include "ISO 123:2020"
      end

      it "not using cache refreshes the cached entry" do
        expect(db_cache).not_to receive(:[])
        expect(db_cache).to receive(:store)
        entry = subject.send :fetch_entry, "ISO 123", nil, { no_cache: true },
                             :relaton_iso, db: db_cache, id: :key
        expect(entry).to include "ISO 123:2020"
      end
    end
  end

  context "pubid cache keys" do
    let(:db) { Relaton::Db.new "testcache", nil }

    def iso_item(id, published: nil)
      docid = Relaton::Bib::Docidentifier.new(content: id, type: "ISO",
                                              primary: true)
      date = []
      if published
        date << Relaton::Bib::Date.new(type: "published", at: published)
      end
      Relaton::Iso::ItemData.new(docidentifier: [docid], date: date,
                                 fetched: Date.today.to_s)
    end

    def doc_files
      Dir["testcache/v2/docs/**/*.xml"]
    end

    after { FileUtils.rm_rf "testcache" }

    it "keeps an undated query and its dated document in one file" do
      item = iso_item("ISO 19115-1:2014")
      expect(Relaton::Iso::Bibliography).to receive(:get)
        .with("ISO 19115-1", nil, {}).once.and_return item
      expect(db.fetch("ISO 19115-1").docidentifier.first.content)
        .to eq "ISO 19115-1:2014"
      expect(db.fetch("ISO 19115-1:2014").docidentifier.first.content)
        .to eq "ISO 19115-1:2014"
      expect(doc_files.size).to eq 1
    end

    it "writes one file for queries that differ only by date range" do
      expect(Relaton::Iso::Bibliography).to receive(:get).once
        .and_return iso_item("ISO 19115-1:2014", published: "2014-04-01")
      %w[2010 2012 2014].each do |after|
        bib = db.fetch "ISO 19115-1", nil, publication_date_after: after
        expect(bib.docidentifier.first.content).to eq "ISO 19115-1:2014"
      end
      expect(doc_files.size).to eq 1
    end

    it "does not answer a date range with an edition outside it" do
      expect(Relaton::Iso::Bibliography).to receive(:get).twice
        .and_return iso_item("ISO 19115-1:2014", published: "2014-04-01")
      db.fetch "ISO 19115-1", nil, publication_date_after: "2010"
      db.fetch "ISO 19115-1", nil, publication_date_after: "2020"
    end

    it "keeps the cached document when a no_cache fetch finds nothing" do
      expect(Relaton::Iso::Bibliography).to receive(:get)
        .and_return(iso_item("ISO 19115-1:2014"), nil)
      db.fetch "ISO 19115-1:2014"
      db.fetch "ISO 19115-1:2014", nil, no_cache: true
      expect(db.fetch_db("ISO 19115-1:2014")).to be_instance_of Relaton::Iso::ItemData
    end

    it "does not raise for a reference the flavor reads as a miss" do
      expect(Relaton::Adobe::Bibliography).to receive(:get).and_return nil
      expect(db.fetch("Adobe Glyph List")).to be_nil
    end

    it "raises for a reference the flavor cannot parse" do
      expect(Relaton::Iso::Bibliography).not_to receive(:get)
      expect { db.fetch "ISO 111111" }.to raise_error Pubid::Errors::ParseError
    end

    it "keeps the string key for a processor with no pubid class" do
      processor = Relaton::Db::Registry.instance[:relaton_iso]
      allow(processor).to receive(:pubid_class).and_return nil
      allow(processor).to receive(:cache_key).and_return nil
      expect(Relaton::Iso::Bibliography).to receive(:get).once
        .and_return iso_item("ISO 123")
      2.times { db.fetch "ISO 123" }
      expect(Relaton::Db::Cache.new("testcache").rows.map { _1["key"] })
        .to eq ["ISO(ISO 123)"]
    end
  end

  context "#pub_date_in_range?" do
    let(:xml_with_date) do
      <<~XML
        <bibitem id="ISO123">
          <title>Test</title>
          <date type="published"><on>2019-06-15</on></date>
        </bibitem>
      XML
    end

    let(:xml_year_only) do
      <<~XML
        <bibitem id="ISO123">
          <title>Test</title>
          <date type="published"><on>2019</on></date>
        </bibitem>
      XML
    end

    let(:xml_year_month) do
      <<~XML
        <bibitem id="ISO123">
          <title>Test</title>
          <date type="published"><on>2019-06</on></date>
        </bibitem>
      XML
    end

    let(:xml_no_date) do
      <<~XML
        <bibitem id="ISO123">
          <title>Test</title>
        </bibitem>
      XML
    end

    it "returns true when date is within range" do
      result = subject.send(
        :pub_date_in_range?, xml_with_date,
        publication_date_after: "2019-01-01",
        publication_date_before: "2020-01-01"
      )
      expect(result).to be true
    end

    it "returns false when date is before :publication_date_after" do
      result = subject.send(
        :pub_date_in_range?, xml_with_date,
        publication_date_after: "2020-01-01"
      )
      expect(result).to be false
    end

    it "returns false when date is on or after " \
       ":publication_date_before (exclusive)" do
      result = subject.send(
        :pub_date_in_range?, xml_with_date,
        publication_date_before: "2019-06-15"
      )
      expect(result).to be false
    end

    it "returns true when date equals :publication_date_after (inclusive)" do
      result = subject.send(
        :pub_date_in_range?, xml_with_date,
        publication_date_after: "2019-06-15"
      )
      expect(result).to be true
    end

    it "handles year-only dates" do
      result = subject.send(
        :pub_date_in_range?, xml_year_only,
        publication_date_after: "2018-01-01",
        publication_date_before: "2020-01-01"
      )
      expect(result).to be true
    end

    it "handles year-month dates" do
      result = subject.send(
        :pub_date_in_range?, xml_year_month,
        publication_date_after: "2019-05-01",
        publication_date_before: "2019-07-01"
      )
      expect(result).to be true
    end

    it "returns false when no published date exists" do
      result = subject.send(:pub_date_in_range?, xml_no_date,
                            publication_date_after: "2019-01-01")
      expect(result).to be false
    end

    it "returns true with only :publication_date_after when date matches" do
      result = subject.send(:pub_date_in_range?, xml_with_date,
                            publication_date_after: "2019-01-01")
      expect(result).to be true
    end

    it "returns true with only :publication_date_before when date matches" do
      result = subject.send(:pub_date_in_range?, xml_with_date,
                            publication_date_before: "2020-01-01")
      expect(result).to be true
    end

    it "accepts YYYY and YYYY-MM bounds" do
      expect(subject.send(:pub_date_in_range?, xml_with_date,
                          publication_date_after: "2019",
                          publication_date_before: "2019-07")).to be true
      expect(subject.send(:pub_date_in_range?, xml_with_date,
                          publication_date_after: "2019-07")).to be false
    end
  end

  context "#std_id" do
    it "keeps the publication date range out of the key" do
      id, code = subject.send(
        :std_id, "ISO 19115-1", nil,
        { publication_date_after: "2018-01-01",
          publication_date_before: "2020-12-31" },
        :relaton_iso
      )
      expect(id).to eq "ISO(ISO 19115-1)"
      expect(code).to eq "ISO 19115-1"
    end

    it "combines with year and all_parts" do
      id, = subject.send(
        :std_id, "ISO 19115-1", "2014",
        { all_parts: true, publication_date_after: "2014-01-01" },
        :relaton_iso
      )
      expect(id).to eq "ISO(ISO 19115-1:2014 (all parts))"
    end
  end

  context "#check_bibliocache with date options" do
    let(:db) { Relaton::Db.new "testcache", nil }

    before(:each) do
      db.save_entry "ISO(ISO 123)", <<~XML
        <bibitem id="ISO123">
          <fetched>#{Date.today}</fetched>
          <title>Test</title>
          <date type="published"><on>2019-06-15</on></date>
        </bibitem>
      XML
    end

    after(:each) { db.clear }

    it "returns base cached entry when date matches" do
      item = db.send(
        :check_bibliocache, "ISO 123", nil,
        { publication_date_after: "2019-01-01",
          fetch_db: true }, :relaton_iso
      )
      expect(item).to be_instance_of(Relaton::Iso::ItemData)
    end

    it "does not return base cached entry when date does not match" do
      item = db.send(
        :check_bibliocache, "ISO 123", nil,
        { publication_date_after: "2020-01-01",
          fetch_db: true }, :relaton_iso
      )
      expect(item).to be_nil
    end
  end

  context "class methods" do
    it "::init_bib_caches" do
      expect(FileUtils).to receive(:rm_rf).with(/\/\.relaton\/cache$/)
      expect(FileUtils).to receive(:rm_rf).with(/testcache\/cache$/)
      expect(Relaton::Db).to receive(:new).with(/\/\.relaton\/cache$/,
                                                /testcache\/cache$/)
      Relaton::Db.init_bib_caches(global_cache: true, local_cache: "testcache",
                                  flush_caches: true)
    end
  end

  context "modifing database" do
    let(:db) { Relaton::Db.new "testcache", "testcache2" }

    before(:each) do
      db.save_entry "ISO(ISO 123)", "<bibitem id='ISO123></bibitem>"
    end

    context "move to new dir" do
      let(:db) { Relaton::Db.new "global_cache", "local_cache" }

      after(:each) do
        FileUtils.rm_rf "global_cache"
        FileUtils.rm_rf "local_cache"
      end

      it "global cache" do
        expect(File.exist?("global_cache")).to be true
        expect(db.mv("testcache")).to eq "testcache"
        expect(File.exist?("testcache")).to be true
        expect(File.exist?("global_cache")).to be false
      end

      it "local cache" do
        expect(File.exist?("local_cache")).to be true
        expect(db.mv("testcache2", type: :local)).to eq "testcache2"
        expect(File.exist?("testcache2")).to be true
        expect(File.exist?("local_cache")).to be false
      end
    end

    it "warn if moving in existed dir" do
      expect(File).to receive(:exist?).with("new_cache_dir").and_return true
      allow(File).to receive(:exist?).and_call_original
      expect do
        expect(db.mv("new_cache_dir")).to be_nil
      end.to output(
        /\[relaton-db\] INFO: target directory exists/,
      ).to_stderr_from_any_process
    end

    it "clear" do
      expect(Relaton::Db::Cache.new("testcache").all).to be_any
      expect(Relaton::Db::Cache.new("testcache2").all).to be_any
      db.clear
      expect(Relaton::Db::Cache.new("testcache").all).to be_empty
      expect(Relaton::Db::Cache.new("testcache2").all).to be_empty
    end
  end

  context "query in local DB" do
    let(:db) { Relaton::Db.new "testcache", "testcache2" }

    before(:each) do
      db.save_entry "ISO(ISO 123)", <<~DOC
        <bibitem id='ISO123'>
          <title>The first test</title><edition>2</edition><date type="published"><on>2011-10-12</on></date>
        </bibitem>
      DOC
      db.save_entry "IEC(IEC 123)", <<~DOC
        <bibitem id="IEC123">
          <title>The second test</title><edition>1</edition><date type="published"><on>2015-12</on></date>
        </bibitem>
      DOC
    end

    after(:each) { db.clear }

    it "one document" do
      expect { db.fetch_db "ISO((ISO 124)" }
        .to raise_error Relaton::UnknownReferenceError
      item = db.fetch_db "ISO(ISO 123)"
      expect(item).to be_instance_of Relaton::Iso::ItemData
    end

    it "all documents" do
      items = db.fetch_all
      expect(items.size).to be 2
      expect(items[0]).to be_instance_of Relaton::Iec::ItemData
      expect(items[1]).to be_instance_of Relaton::Iso::ItemData
    end

    context "search for text" do
      it do
        items = db.fetch_all "test"
        expect(items.size).to eq 2
        items = db.fetch_all "first"
        expect(items.size).to eq 1
        expect(items[0].id).to eq "ISO123"
      end

      it "with spaces in text" do
        items = db.fetch_all "first test"
        expect(items.size).to eq 1
        expect(items[0].id).to eq "ISO123"
      end

      it "in attributes" do
        items = db.fetch_all "123"
        expect(items.size).to eq 2
        items = db.fetch_all "ISO"
        expect(items.size).to eq 1
        expect(items[0].id).to eq "ISO123"
      end

      it "and fail" do
        items = db.fetch_all "bibitem"
        expect(items.size).to eq 0
      end

      it "and edition" do
        items = db.fetch_all "123", edition: "2"
        expect(items.size).to eq 1
        expect(items[0].id).to eq "ISO123"
      end

      it "and year" do
        items = db.fetch_all "123", year: 2015
        expect(items.size).to eq 1
        expect(items[0].id).to eq "IEC123"
      end
    end
  end

  it "returns docid type" do
    db = Relaton::Db.new "testcache", "testcache2"
    expect(db.docid_type("CN(GB/T 1.1)")).to eq ["Chinese Standard", "GB/T 1.1"]
  end

  context "#fetch" do
    it "doesn't use cache" do
      docid = Relaton::Bib::Docidentifier.new content: "ISO 19115-1",
                                              type: "ISO"
      item = Relaton::Iso::ItemData.new docid: [docid]
      expect(Relaton::Iso::Bibliography).to receive(:get)
        .with("ISO 19115-1", nil, {}).and_return item
      bib = subject.fetch("ISO 19115-1", nil, {})
      expect(bib).to be_instance_of Relaton::Iso::ItemData
    end

    it "when no local db" do
      docid = Relaton::Bib::Docidentifier.new(content: "ISO 19115-1",
                                              type: "ISO")
      item = Relaton::Iso::ItemData.new(docidentifier: [docid],
                                        fetched: Date.today.to_s)
      expect(Relaton::Iso::Bibliography).to receive(:get)
        .with("ISO 19115-1", nil, {}).and_return item
      db = Relaton::Db.new "testcache", nil
      bib = db.fetch("ISO 19115-1", nil, {})
      expect(bib).to be_instance_of Relaton::Iso::ItemData
    end

    it "document with net retries" do
      registry = subject.instance_variable_get(:@registry)
      expect(registry.processors[:relaton_ietf]).to receive(:get)
        .and_raise(Relaton::RequestError).exactly(3).times
      expect do
        subject.fetch "RFC 8341", nil, retries: 3
      end.to raise_error Relaton::RequestError
    end

    it "strip reference" do
      expect(subject).to receive(:combine_doc)
        .with("ISO 19115-1", nil, {}, :relaton_iso)
        .and_return :doc
      expect(subject.fetch(" ISO 19115-1 ", nil, {})).to be :doc
    end

    # Routing check: a bare `CIPM ...` reference carries no `BIPM` prefix, so
    # this asserts the registry still resolves it to the BIPM processor and that
    # `#fetch` hands back the flavor's own item. The flavor's retrieval (index
    # lookup, document fetch) belongs to spec/bipm, so `Bibliography.get` is
    # stubbed — no cassette, no index download.
    it "BIPM Meeting" do
      docid = Relaton::Bib::Docidentifier.new(
        content: "CIPM 43rd Meeting (1950)", type: "BIPM",
      )
      item = Relaton::Bipm::ItemData.new docidentifier: [docid]
      expect(Relaton::Bipm::Bibliography).to receive(:get)
        .with("CIPM Meeting 43", nil, {}).and_return item
      bib = subject.fetch("CIPM Meeting 43")
      expect(bib).to be_instance_of Relaton::Bipm::ItemData
      expect(bib.docidentifier.first.content).to eq "CIPM 43rd Meeting (1950)"
    end

    # Routing check: `#fetch` must hand an `IALA ...` reference to the IALA
    # processor. The flavor's retrieval belongs to spec/iala, so
    # `Bibliography.get` is stubbed.
    it "IALA" do
      docid = Relaton::Bib::Docidentifier.new(
        content: "IALA S1070 Ed 2.0", type: "IALA",
      )
      item = Relaton::Iala::ItemData.new docidentifier: [docid]
      expect(Relaton::Iala::Bibliography).to receive(:get)
        .with("IALA S1070", nil, {}).and_return item
      bib = subject.fetch("IALA S1070")
      expect(bib).to be_instance_of Relaton::Iala::ItemData
      expect(bib.docidentifier.first.content).to eq "IALA S1070 Ed 2.0"
    end
  end

  it "fetch std" do
    docid = Relaton::Bib::Docidentifier.new(content: "ISO 19115-1", type: "ISO")
    item = Relaton::Iso::ItemData.new(docidentifier: [docid],
                                      fetched: Date.today.to_s)
    expect(Relaton::Iso::Bibliography).to receive(:get)
      .with("ISO 19115-1", nil, {}).and_return item
    db = Relaton::Db.new "testcache", nil
    bib = db.fetch_std("ISO 19115-1", nil, :relaton_iso, {})
    expect(bib).to be_instance_of Relaton::Iso::ItemData
  end

  it "fetch std with the flavor the caller names" do
    expect(Relaton::Iso::Bibliography).not_to receive(:get)
    expect(Relaton::Iec::Bibliography).to receive(:get)
      .with("ISO 19115-1", nil, {}).and_return nil
    Relaton::Db.new(nil, nil).fetch_std("ISO 19115-1", nil, :relaton_iec, {})
  end

  context "async fetch" do
    let(:queue) { Queue.new }

    it "success" do
      refs = ["ITU-T G.993.5", "ITU-T G.994.1", "ITU-T H.264.1", "ITU-T H.740",
              "ITU-T Y.1911", "ITU-T Y.2012", "ITU-T Y.2206", "ITU-T O.172",
              "ITU-T G.780/Y.1351", "ITU-T G.711", "ITU-T G.1011"]
      results = []
      refs.each do |ref|
        expect(subject).to receive(:fetch).with(ref, nil, {}).and_return :result
        subject.fetch_async(ref) { |r| queue << [r, ref] }
      end
      Timeout.timeout(60) { refs.size.times { results << queue.pop } }
      results.each do |result|
        expect(result[0]).to be :result
      end
    end

    it "BIPM i18n" do
      refs = ["CGPM -- Resolution (1889)", "CGPM -- Résolution (1889)",
              "CGPM -- Réunion 9 (1948)", "CGPM -- Meeting 9 (1948)"]
      results = []
      refs.each do |ref|
        expect(subject).to receive(:fetch).with(ref, nil, {}).and_return :result
        subject.fetch_async(ref) { |r| queue << [r, ref] }
      end
      Timeout.timeout(60) { refs.size.times { results << queue.pop } }
      results.each do |result|
        expect(result[0]).to be :result
      end
    end

    it "prefix not found", vcr: "rfc_unsuccess" do
      result = ""
      subject.fetch_async("ABC 123456") { |r| queue << r }
      Timeout.timeout(5) { result = queue.pop }
      expect(result).to be_nil
    end

    it "handle HTTP request error" do
      expect(subject).to receive(:fetch).and_raise Relaton::RequestError
      subject.fetch_async("ISO REF") { |r| queue << r }
      result = Timeout.timeout(5) { queue.pop }
      expect(result).to be_instance_of Relaton::RequestError
    end

    it "handle other errors" do
      expect(subject).to receive(:fetch).and_raise Errno::EACCES
      log_io = Relaton.logger_pool[:default].instance_variable_get(:@logdev)
      expect(log_io).to receive(:write).with(
        "[relaton-db] ERROR: `ISO REF` -- Permission denied\n",
      )
      subject.fetch_async("ISO REF") { |r| queue << r }
      result = Timeout.timeout(5) { queue.pop }
      expect(result).to be_nil
    end

    it "use threads number from RELATON_FETCH_PARALLEL" do
      expect(ENV).to receive(:[]).with("RELATON_FETCH_PARALLEL").and_return(1)
      allow(ENV).to receive(:[]).and_call_original
      expect(Relaton::Db::WorkersPool).to receive(:new).with(1).and_call_original
      expect(subject).to receive(:fetch).with("ITU-T G.993.5", nil, {})
      subject.fetch_async("ITU-T G.993.5") { |r| queue << r }
      Timeout.timeout(50) { queue.pop }
    end
  end

  context "#fetch parse-first routing (relaton#205)" do
    it "routes by the parsed pubid class and keys the cache with that parse" do
      expect(Pubid).to receive(:parse).with("ISO 8601-1:2021").once.and_call_original
      expect(Relaton::Db::Registry.instance[:relaton_iso])
        .not_to receive(:cache_pubid)
      expect(Relaton::Iso::Bibliography).to receive(:get).with(
        "ISO 8601-1:2021", anything, anything
      ).and_return(nil)
      subject.fetch("ISO 8601-1:2021")
    end

    it "routes a co-published identifier to the flavor its printed form names first" do
      expect(Relaton::Iec::Bibliography).not_to receive(:get)
      expect(Relaton::Iso::Bibliography).to receive(:get)
        .with("ISO/IEC 27001:2022", anything, anything).and_return(nil)
      subject.fetch("ISO/IEC 27001:2022")
    end

    it "raises for a DOI-shaped string no flavor claims" do
      expect(Relaton::Un::Bibliography).not_to receive(:get)
      expect { subject.fetch("10.17487/RFC3986") }
        .to raise_error Relaton::UnknownReferenceError
    end

    it "hands an IEC reference with many colons to IEC unchanged" do
      ref = "IEC 60034-1:1969+AMD1:1977+AMD2:1979+AMD3:1980 CSV"
      expect(Relaton::Iec::Bibliography).to receive(:get)
        .with(ref, anything, anything).and_return(nil)
      subject.fetch ref
    end

    it "raises for a reference no flavor recognizes" do
      expect { subject.fetch("ABC 123456") }
        .to raise_error Relaton::UnknownReferenceError, /ABC 123456/
    end
  end

end
