require "relaton/sae/data_fetcher"

describe Relaton::Sae::DataFetcher, :no_index_fixture do
  let(:pages) do
    Dir["fixtures/crossref/page-*.json"].sort.map do |f|
      File.read f
    end
  end
  let(:url) { %r{\Ahttps://api\.crossref\.org/prefixes/10\.4271/works\?} }

  def stub_page(cursor, body)
    stub_request(:get, url)
      .with(query: hash_including("filter" => "type:standard",
                                  "cursor" => cursor))
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })
  end

  def crawl
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        described_class.fetch("sae-crossref", output: "data", format: "yaml")
        yield dir
      end
    end
  end

  before do
    # Pacing and back-off waits are real `sleep`s; the crawl logic is what is
    # under test here.
    allow_any_instance_of(described_class).to receive(:sleep)
    allow_any_instance_of(Relaton::Core::Pacer).to receive(:wait)
    # The producer index is a pool entry keyed by a relative file name, so a
    # previous example's rows would survive into the next crawl.
    Relaton::Index.close(:sae)
    stub_page "*", pages[0]
    stub_page "cursor-2", pages[1]
    stub_page "cursor-3", pages[2]
  end

  it "writes one file per Crossref record" do
    crawl do
      files = Dir["data/*.yaml"].map { |f| File.basename f }.sort
      expect(files.size).to eq 11
      expect(files).to include "sae-j3016_202104.yaml", "sae-ams4121j.yaml"
    end
  end

  it "gives a record SAE's own edition code as its primary identifier" do
    crawl do
      item = Relaton::Sae::Item.from_yaml File.read("data/sae-j3016_202104.yaml")
      ids = item.docidentifier.map { |d| [d.type, d.content, d.primary] }
      expect(ids).to eq [["SAE", "SAE J3016_202104", true],
                         ["DOI", "10.4271/j3016_202104", nil]]
      expect([item.ext.doctype.content, item.ext.flavor]).to eq %w[standard sae]
      expect(item.title.first.content).to start_with "Taxonomy and Definitions"
      expect(item.date.map do |d|
        [d.type, d.at.to_s]
      end).to include ["approved", "2021-04-30"]
    end
  end

  # A daily crawl must leave an unchanged record byte for byte, or each run
  # commits the whole corpus (hand-off
  # relaton__relaton__sae-drop-fetched-from-crawl). The consumer sets
  # `fetched` when it reads a document.
  it "writes no fetch date, so a later crawl leaves the files unchanged" do
    first = crawl { Dir["data/*.yaml"].to_h { |f| [f, File.read(f)] } }
    allow(Date).to receive(:today).and_return(Date.today + 1)
    second = crawl { Dir["data/*.yaml"].to_h { |f| [f, File.read(f)] } }
    expect(first.values).to all(satisfy { |yaml| !yaml.match?(/^fetched:/) })
    expect(second).to eq first
  end

  # A record Crossref holds in addition to the fixture pages.
  def add_work(doi, approved, first: true)
    page = JSON.parse(pages[1])
    twin = page["message"]["items"].find { |i| i["DOI"] == "10.4271/j3016_202104" }
    work = twin.merge("DOI" => doi, "approved" => { "date-parts" => [approved] })
    items = page["message"]["items"]
    first ? items.unshift(work) : items.push(work)
    stub_page "cursor-2", page.to_json
  end

  def index_rows
    YAML.load_file("#{Relaton::Sae::INDEXFILE}.yaml", permitted_classes: [Symbol])
  end

  it "indexes every record, keyed by its edition code" do
    crawl do
      ids = index_rows.map { |r| Pubid::Sae::Identifier.from_hash(r[:id]).to_s }
      expect(ids).to contain_exactly(
        "SAE J3016_201401", "SAE J3016_201609", "SAE J3016_201806",
        "SAE J3016_202104", "SAE J3016_202609", "SAE J3194_201911",
        "SAE J2337/2_201702", "SAE J1939DA_201702",
        "SAE AMS4121:1946", "SAE AMS4121H:2013", "SAE AMS4121J:2017"
      )
      row = index_rows.find { |r| r[:file] == "data/sae-ams4121j.yaml" }
      expect(row[:id]).to include("number" => "4121", "revision" => "J")
    end
  end

  it "gives a record the code SAE prints, not the DOI's spelling" do
    add_work "10.4271/amsqqa250/4b", [2019, 5, 1]
    crawl do
      item = Relaton::Sae::Item.from_yaml File.read("data/sae-amsqqa250-4b.yaml")
      expect(item.docidentifier.first.content).to eq "SAE AMS-QQ-A-250/4B"
    end
  end

  # One row that fails to deserialize makes Relaton::Index reject the whole
  # index, so the data file is written and the row is skipped and reported.
  it "reports a record pubid cannot parse instead of indexing it" do
    add_work "10.4271/cpgm2016", [2016, 1, 1]
    fetcher = nil
    allow(described_class).to(receive(:new).and_wrap_original do |m, *a|
      fetcher = m.call(*a)
    end)
    crawl do
      expect(File).to exist "data/sae-cpgm2016.yaml"
      expect(index_rows.size).to eq 11
      errors = fetcher.instance_variable_get(:@errors).select { |_, v| v.is_a? String }
      expect(errors.values).to contain_exactly a_string_including("SAE CPGM2016")
    end
  end

  it "indexes two editions of one year under their own months" do
    add_work "10.4271/j3016_202101", [2021, 1, 4]
    crawl do
      files = index_rows.select { |r| r[:id].dig("date", "year") == 2021 }
        .map { |r| r[:file] }
      expect(files).to contain_exactly "data/sae-j3016_202101.yaml",
                                       "data/sae-j3016_202104.yaml"
    end
  end

  # Two DOIs can spell one code (`ams-4121j`, `ams4121j`). They share an index
  # key, and the later approval keeps the row in either crawl order.
  [true, false].each do |first|
    it "keeps the later record of two that share a key (#{first ? 'older first' : 'older last'})" do
      add_work "10.4271/ams-4121j", [2017, 1, 1], first: first
      crawl do
        files = index_rows.select { |r| r[:id]["revision"] == "J" }.map { |r| r[:file] }
        expect(files).to eq ["data/sae-ams4121j.yaml"]
      end
    end
  end

  it "retries a page after a transport error" do
    stub_request(:get, url).with(query: hash_including("cursor" => "*"))
      .to_raise(Net::ReadTimeout).then.to_return(status: 200, body: pages[0])
    crawl { expect(Dir["data/*.yaml"].size).to eq 11 }
  end

  it "retries a page Crossref throttles" do
    stub_request(:get, url).with(query: hash_including("cursor" => "*"))
      .to_return({ status: 429, body: "",
                   headers: { "x-rate-limit-interval" => "1s" } },
                 { status: 200, body: pages[0] })
    crawl { expect(Dir["data/*.yaml"].size).to eq 11 }
  end

  it "fails the crawl when Crossref keeps failing" do
    stub_request(:get,
                 url).with(query: hash_including("cursor" => "*")).to_return(status: 503)
    expect do
      crawl do
        nil
      end
    end.to raise_error Relaton::RequestError, /after 5 attempts/
  end

  it "refuses an unknown source" do
    expect { described_class.new("data", "yaml").fetch("sae-web") }
      .to raise_error ArgumentError, /sae-web/
  end
end
