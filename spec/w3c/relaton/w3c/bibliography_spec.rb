# frozen_string_literal: true

describe Relaton::W3c::Bibliography do
  before do
    allow_any_instance_of(Relaton::Index::Type).to receive(:actual?).and_return(false)
    allow_any_instance_of(Relaton::Index::FileIO).to receive(:check_file).and_return(nil)
  end

  it "raise error" do
    expect(Relaton::Index).to receive(:find_or_create).and_raise SocketError
    expect { described_class.get("W3C REC-json-ld11-20200716") }
      .to raise_error Relaton::RequestError
  end

  it "get by title", vcr: "cr_json_ld11" do
    doc = described_class.get("W3C CR-json-ld11-20200316")
    expect(doc).to be_instance_of Relaton::W3c::ItemData
    xml = doc.to_xml(bibdata: true)
    file = "fixtures/cr_json_ld11.xml"
    File.write(file, xml, encoding: "UTF-8") unless File.exist?(file)
    expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
      .gsub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s)
  end

  context "dated" do
    it "fetch", vcr: "rec_xml_names_20091208" do
      doc = described_class.get("W3C REC-xml-names-20091208")
      expect(doc.title.first.content).to eq "Namespaces in XML 1.0 (Third Edition)"
    end
  end

  context "undated" do
    it "fetch", vcr: "rec_xml_names" do
      doc = described_class.get("W3C xml-names")
      xml = Relaton::W3c::Bibdata.to_xml(doc)
      expect(xml).to be_equivalent_to File.read("fixtures/rec_xml_names.xml", encoding: "UTF-8")
        .gsub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s)
      schema = Jing.new "../../grammar/relaton-w3c-compile.rng"
      errors = schema.validate file_xml(xml)
      expect(errors).to eq []
    end
  end

  context "latest version" do
    it "last year", vcr: "last_year" do
      doc = described_class.get("W3C xml-names")
      expect(doc.docidentifier[0].content).to eq "W3C xml-names"
    end

    it "last date", vcr: "last_date" do
      doc = described_class.get("W3C xml-names")
      expect(doc.docidentifier[0].content).to eq "W3C xml-names"
    end
  end

  it "TR type", vcr: "w3c_tr_vocab-adms" do
    doc = described_class.get("W3C vocab-adms")
    expect(doc.docidentifier[0].content).to eq "W3C vocab-adms"
  end

  it "by URL", vcr: "rec_xml_names" do
    doc = described_class.get("https://www.w3.org/TR/xml-names/")
    xml = doc.to_xml(bibdata: true)
    file = "fixtures/rec_xml_names.xml"
    File.write(file, xml, encoding: "UTF-8") unless File.exist?(file)
    expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
      .gsub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s)
  end

  it "W3C xml", vcr: "w3c_xml" do
    doc = described_class.get("W3C xml")
    expect(doc.docidentifier[0].content).to eq "W3C xml"
  end

  it "accepts a parsed pubid", vcr: "rec_xml_names_20091208" do
    pubid = Pubid::W3c::Identifier.parse("W3C REC-xml-names-20091208")
    doc = described_class.get(pubid)
    expect(doc.title.first.content).to eq "Namespaces in XML 1.0 (Third Edition)"
  end

  # The W3C pilot of relaton#189: the index is the machine index on the Pages
  # site, read one shard at a time and held in memory. The documents still come
  # from the data repo.
  context "with the Pages machine index" do
    let(:pages) { Relaton::W3c::Bibliography::PAGES_URL }
    let(:shards) { 2048 }
    let(:fixture_rows) { W3cIndexFixture.index_type.index }

    def shard_of(number)
      format("%<pages>sindex/shard-%<n>05d.json",
             pages: pages, n: Zlib.crc32(number) % shards)
    end

    before do
      # The outer `before` makes every Type stale; the pool must keep the
      # Pages type here, as it does at runtime.
      allow_any_instance_of(Relaton::Index::Type).to receive(:actual?).and_call_original
      Relaton::Index.close(:W3C)
      stub_request(:get, "#{pages}index/manifest.json").to_return(
        status: 200,
        body: { version: 2, index: "index-v2", count: fixture_rows.size,
                shards: shards, key: "root-number", algorithm: "crc32" }.to_json,
      )
    end

    it "opens the index on the Pages site" do
      expect(Relaton::Index).to receive(:find_or_create).with(
        :W3C, pages_url: "https://relaton.github.io/relaton-data-w3c/",
              pubid_class: Pubid::W3c::Identifier
      ).and_call_original
      described_class.send(:index)
    end

    it "finds the row in one shard, without the whole index" do
      rows = fixture_rows.select { |r| r[:id].root.number.to_s == "xml-names" }
      body = rows.map { |r| { r: r[:id].to_s, file: r[:file], id: r[:id].to_hash } }
      stub_request(:get, shard_of("xml-names")).to_return(status: 200, body: body.to_json)

      pubid = Pubid::W3c::Identifier.parse("W3C REC-xml-names-20091208")
      row = described_class.send(:best_match, pubid)

      expect(row[:id].to_s).to eq "W3C REC-xml-names-20091208"
      expect(a_request(:get, /\.zip\z/)).not_to have_been_made
    end

    # A differently-cased slug keys another shard, so `#loose_match?` needs
    # every row: a miss reads the whole index once, from the Pages site.
    it "reads the whole index once on a miss, for the case-insensitive retry" do
      stub_request(:get, %r{\A#{pages}index/shard-}).to_return(status: 404)
      zip = Zip::OutputStream.write_buffer do |z|
        z.put_next_entry "index-v2.yaml"
        z.write fixture_rows.first(3).map { |r| { id: r[:id].to_hash, file: r[:file] } }.to_yaml
      end.string
      stub_request(:get, "#{pages}index-v2.zip").to_return(status: 200, body: zip)

      2.times do
        described_class.send(:best_match, Pubid::W3c::Identifier.parse("W3C REC-no-such-doc"))
      end
      expect(a_request(:get, "#{pages}index-v2.zip")).to have_been_made.once
    end

    it "raises Relaton::RequestError when the Pages site fails" do
      stub_request(:get, %r{\A#{pages}index/shard-}).to_return(status: 503)
      expect { described_class.get("W3C REC-xml-names-20091208") }
        .to raise_error Relaton::RequestError
    end
  end

  # The point of index-v2: `Index::Type#search` binary-searches on
  # `id.root.number` when it is handed the pubid, instead of scanning all
  # 17,303 rows. Asserted by counting the candidates the bsearch returns --
  # `#best_match` passes no block, so the rows it sees cannot be counted
  # through one.
  it "narrows the index by number instead of scanning it" do
    index = Relaton::Index.find_or_create(:W3C, url: true)
    pubid = Pubid::W3c::Identifier.parse("W3C REC-xml-names-20091208")
    candidates = index.send(:candidates_by_number, pubid)

    expect(candidates.size).to be > 0
    expect(candidates.size).to be < index.index.size / 100
  end

  # `#best_match` selects rows with pubid's asymmetric subset match: the
  # reference on the left, the row on the right. `date` is W3C's only optional
  # component, so an undated reference reaches the dated row and a dated one
  # does not reach a row that states another date. The maturity level is the
  # identifier's class, which `===` compares, so `WD-` never answers for `REC-`.
  context "subset match" do
    def id(ref) = Pubid::W3c::Identifier.parse(ref)

    it "lets an undated reference reach a dated row" do
      expect(id("W3C REC-xml-names") === id("W3C REC-xml-names-19990114"))
        .to be true
    end

    it "is not symmetric" do
      expect(id("W3C REC-xml-names-19990114") === id("W3C REC-xml-names"))
        .to be false
    end

    it "keeps the maturity levels apart" do
      expect(id("W3C WD-xml-names") === id("W3C REC-xml-names-19990114"))
        .to be false
    end
  end

  # `PubId#==` compared its slug with `casecmp?`, but the bsearch key is
  # case-sensitive, so the narrowed range alone would lose this. The full-scan
  # fallback keeps it.
  it "still matches a slug that differs only by case" do
    row = described_class.send :best_match,
                               Pubid::W3c::Identifier.parse("W3C REC-XML-NAMES-20091208")
    expect(row[:file]).to eq "data/rec-xml-names-20091208.yaml"
  end

  # A reference pubid rejects RAISES; relaton lets it propagate so a caller can
  # tell a malformed identifier from an absent document. It is never relabelled
  # as a `RequestError` -- the parse sits outside that rescue. The grammar takes
  # any slug after the publisher prefix, so an empty reference is what actually
  # fails to parse.
  it "raises for a reference pubid cannot parse" do
    expect { described_class.send(:parse_ref, "  ") }
      .to raise_error Pubid::Errors::ParseError
  end

  # W3C dates are opaque digit runs of varying width, so "newest wins" cannot
  # be a plain `to_i`: a legacy 6-digit YYMMDD would always lose to an 8-digit
  # YYYYMMDD however much later it is. The published corpus happens not to
  # contain such a pair, which is exactly why this is pinned.
  describe "date ordering across widths" do
    it "reads a 6-digit YYMMDD as 1990s, so it can beat an earlier 8-digit" do
      expect(described_class.send(:date_key, "980619"))
        .to be > described_class.send(:date_key, "19980512")
    end

    it "keeps a year-less 4-digit MMDD below every real date" do
      expect(described_class.send(:date_key, "0414"))
        .to be < described_class.send(:date_key, "971104")
    end

    it "sorts an undated row lowest" do
      expect(described_class.send(:date_key, nil)).to eq 0
    end
  end

  it "not found" do
    expect { described_class.get("W3C NOT-FOUND") }
      .to output(/Not found/).to_stderr_from_any_process
  end

  private

  def file_xml(xml)
    f = Tempfile.new(["w3c", ".xml"])
    f.write xml
    f.close
    f.path
  end
end
