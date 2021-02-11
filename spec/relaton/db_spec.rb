RSpec.describe Relaton::Db do
  before(:each) { FileUtils.rm_rf %w[testcache testcache2] }

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
      result = nil
      VCR.use_cassette "rfc_8341" do
        db.fetch_async("RFC 8341") { |r| queue << r }
        Timeout.timeout(5) { result = queue.pop }
      end
      expect(result).to be_instance_of RelatonIetf::IetfBibliographicItem
    end

    it "prefix not found" do
      result = ""
      VCR.use_cassette "rfc_unsuccess" do
        db.fetch_async("ABC 123456") { |r| queue << r }
        Timeout.timeout(5) { result = queue.pop }
      end
      expect(result).to be_nil
    end
  end

  context "fetch documents form static cache" do
    let(:db) { Relaton::Db.new nil, nil }

    it "fetches ISO/IEC DIR 1 IEC SUP" do
      bib = db.fetch "ISO/IEC DIR 1 IEC SUP"
      expect(bib).to be_instance_of RelatonIsoBib::IsoBibliographicItem
      expect(bib.docidentifier.first.id).to eq "ISO/IEC DIR 1 IEC SUP"
    end

    it "fetches ISO/IEC DIR 1 ISO SUP" do
      bib = db.fetch "ISO/IEC DIR 1 ISO SUP"
      expect(bib).to be_instance_of RelatonIsoBib::IsoBibliographicItem
      expect(bib.docidentifier.first.id).to eq "ISO/IEC DIR 1 ISO SUP"
    end

    it "fetches ISO/IEC DIR 1" do
      bib = db.fetch "ISO/IEC DIR 1"
      expect(bib).to be_instance_of RelatonIsoBib::IsoBibliographicItem
      expect(bib.docidentifier.first.id).to eq "ISO/IEC DIR 1"
    end

    it "fetches ISO/IEC DIR 2 IEC" do
      bib = db.fetch "ISO/IEC DIR 2 IEC"
      expect(bib).to be_instance_of RelatonIsoBib::IsoBibliographicItem
      expect(bib.docidentifier.first.id).to eq "ISO/IEC DIR 2 IEC"
    end

    it "fetches ISO/IEC DIR 2 ISO" do
      bib = db.fetch "ISO/IEC DIR 2 ISO"
      expect(bib).to be_instance_of RelatonIsoBib::IsoBibliographicItem
      expect(bib.docidentifier.first.id).to eq "ISO/IEC DIR 2 ISO"
    end

    it "fetches ISO/IEC DIR IEC SUP" do
      bib = db.fetch "ISO/IEC DIR IEC SUP"
      expect(bib).to be_instance_of RelatonIsoBib::IsoBibliographicItem
      expect(bib.docidentifier.first.id).to eq "ISO/IEC DIR IEC SUP"
    end

    it "fetches ISO/IEC DIR JTC 1 SUP" do
      bib = db.fetch "ISO/IEC DIR JTC 1 SUP"
      expect(bib).to be_instance_of RelatonIsoBib::IsoBibliographicItem
      expect(bib.docidentifier.first.id).to eq "ISO/IEC DIR JTC 1 SUP"
    end
  end
end
