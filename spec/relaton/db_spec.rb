RSpec.describe Relaton::Db do
  before(:each) { FileUtils.rm_rf %w[testcache testcache2] }

  context "instance methods" do
    subject { Relaton::Db.new nil, nil }

    context "#search_edition_year" do
      it "create bibitem from YAML content" do
        h = { "docid" => [{ "id" => "ISO 123", type: "ISO", "primary" => true }] }
        expect(YAML).to receive(:safe_load).with(:content).and_return h
        allow(YAML).to receive(:safe_load).and_call_original
        item = subject.send :search_edition_year, "iso/item.yaml", :content, nil, nil
        expect(item).to be_instance_of RelatonIsoBib::IsoBibliographicItem
      end
    end

    context "#new_bib_entry" do
      it "warn if cached entry is not_found" do
        id = "ISO(ISO 123)"
        db = double "db"
        expect(db).to receive(:[]).with(id).and_return "not_found"
        expect do
          entry = subject.send :new_bib_entry, "ISO 123", nil, {}, :relaton_iso, db: db, id: id
          expect(entry).to be_nil
        end.to output("[relaton] (ISO 123) not found.\n").to_stderr
      end
    end

    context "#combine_doc" do
      it "retrun nil for BIPM documents" do
        code = double "code"
        expect(code).not_to receive(:split)
        expect(subject.send(:combine_doc, code, nil, {}, :relaton_bipm)).to be_nil
      end
    end
  end

  context "class methods" do
    it "::init_bib_caches" do
      expect(FileUtils).to receive(:rm_rf).with(/\/\.relaton\/cache$/)
      expect(FileUtils).to receive(:rm_rf).with(/testcache\/cache$/)
      expect(Relaton::Db).to receive(:new).with(/\/\.relaton\/cache$/, /testcache\/cache$/)
      Relaton::Db.init_bib_caches(global_cache: true, local_cache: "testcache", flush_caches: true)
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
      expect(File).to receive(:exist?).with("new_cache_dir")
        .and_return true
      expect do
        expect(db.mv("new_cache_dir")).to be_nil
      end.to output(/\[relaton\] WARNING: target directory exists/).to_stderr
    end

    it "clear" do
      expect(File.exist?("testcache/iso")).to be true
      expect(File.exist?("testcache2/iso")).to be true
      db.clear
      expect(File.exist?("testcache/iso")).to be false
      expect(File.exist?("testcache2/iso")).to be false
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
      item = db.fetch_db "ISO((ISO 124)"
      expect(item).to be_nil
      item = db.fetch_db "ISO(ISO 123)"
      expect(item).to be_instance_of RelatonIsoBib::IsoBibliographicItem
    end

    it "all documents" do
      items = db.fetch_all
      expect(items.size).to be 2
      expect(items[0]).to be_instance_of RelatonIec::IecBibliographicItem
      expect(items[1]).to be_instance_of RelatonIsoBib::IsoBibliographicItem
    end

    context "search for text" do
      it do
        items = db.fetch_all "test"
        expect(items.size).to eq 2
        items = db.fetch_all "first"
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

  it "doesn't use cache" do
    db = Relaton::Db.new nil, nil
    VCR.use_cassette "iso_19115_1" do
      bib = db.fetch("ISO 19115-1", nil, {})
      expect(bib).to be_instance_of RelatonIsoBib::IsoBibliographicItem
    end
  end

  it "fetch when no local db" do
    db = Relaton::Db.new "testcache", nil
    VCR.use_cassette "iso_19115_1" do
      bib = db.fetch("ISO 19115-1", nil, {})
      expect(bib).to be_instance_of RelatonIsoBib::IsoBibliographicItem
    end
  end

  it "fetch std" do
    db = Relaton::Db.new "testcache", nil
    VCR.use_cassette "iso_19115_1" do
      bib = db.fetch_std("ISO 19115-1", nil, :relaton_iso, {})
      expect(bib).to be_instance_of RelatonIsoBib::IsoBibliographicItem
    end
  end

  it "fetch document with net retries" do
    db = Relaton::Db.new nil, nil
    expect(db.instance_variable_get(:@registry).processors[:relaton_ietf]).to receive(:get)
      .and_raise(RelatonBib::RequestError).exactly(3).times
    expect { db.fetch "RFC 8341", nil, retries: 3 }.to raise_error RelatonBib::RequestError
  end

  context "async fetch" do
    let(:db) { Relaton::Db.new nil, nil }
    let(:queue) { Queue.new }

    it "success" do
      refs = ["ITU-T G.993.5", "ITU-T G.994.1", "ITU-T H.264.1", "ITU-T H.740",
              "ITU-T Y.1911", "ITU-T Y.2012", "ITU-T Y.2206", "ITU-T O.172",
              "ITU-T G.780/Y.1351", "ITU-T G.711", "ITU-T G.1011"]
      results = []
      refs.each do |ref|
        expect(db).to receive(:fetch).with(ref, nil, {}).and_return :result
        db.fetch_async(ref) { |r| queue << [r, ref] }
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
        expect(db).to receive(:fetch).with(ref, nil, {}).and_return :result
        db.fetch_async(ref) { |r| queue << [r, ref] }
      end
      Timeout.timeout(60) { refs.size.times { results << queue.pop } }
      results.each do |result|
        expect(result[0]).to be :result
      end
    end

    it "prefix not found" do
      result = ""
      VCR.use_cassette "rfc_unsuccess" do
        db.fetch_async("ABC 123456") { |r| queue << r }
        Timeout.timeout(5) { result = queue.pop }
      end
      expect(result).to be_nil
    end

    it "handle HTTP request error" do
      expect(db).to receive(:fetch).and_raise RelatonBib::RequestError
      db.fetch_async("ISO REF") { |r| queue << r }
      result = Timeout.timeout(5) { queue.pop }
      expect(result).to be_instance_of RelatonBib::RequestError
    end

    it "handle other errors" do
      expect(db).to receive(:fetch).and_raise Errno::EACCES
      expect do
        db.fetch_async("ISO REF") { |r| queue << r }
        result = Timeout.timeout(5) { queue.pop }
        expect(result).to be_nil
      end.to output("[relaton] ERROR: ISO REF -- Permission denied\n").to_stderr
    end

    it "use threads number from RELATON_FETCH_PARALLEL" do
      expect(ENV).to receive(:[]).with("RELATON_FETCH_PARALLEL").and_return(1)
      allow(ENV).to receive(:[]).and_call_original
      expect(Relaton::WorkersPool).to receive(:new).with(1).and_call_original
      expect(db).to receive(:fetch).with("ITU-T G.993.5", nil, {})
      db.fetch_async("ITU-T G.993.5") { |r| queue << r }
      Timeout.timeout(50) { queue.pop }
    end
  end
end
