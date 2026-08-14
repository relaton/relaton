require "relaton/itu/data_merge_r"
require "relaton/itu/data_fetcher"
require "tmpdir"
require "yaml"

describe Relaton::Itu::DataMergeR do
  def item(id, doctype: "recommendation", date: nil, source: nil, title: "Harvested title")
    Relaton::Itu::ItemData.new(
      docidentifier: [Relaton::Itu::Docidentifier.new(type: "ITU", content: id, primary: true)],
      title: [Relaton::Bib::Title.new(type: "main", content: title, language: "en", script: "Latn")],
      date: date ? [Relaton::Bib::Date.new(type: "published", at: date)] : [],
      source: source ? [Relaton::Bib::Uri.new(type: "pdf", content: source)] : [],
      language: ["en"], script: ["Latn"], type: "standard",
      ext: Relaton::Itu::Ext.new(doctype: Relaton::Itu::Doctype.new(content: doctype), flavor: "itu"),
    )
  end

  around do |example|
    Dir.mktmpdir("relaton-itu-merge") do |dir|
      @dir = dir
      Dir.chdir(dir) { example.run }
    end
  end

  let(:fetcher) { Relaton::Itu::DataFetcher.new "data", "yaml" }

  before do
    FileUtils.mkdir_p "data"
    allow(fetcher).to receive(:index).and_return(double("index", add_or_update: nil, save: nil))
  end

  def publish(id, **opts)
    file = fetcher.output_file id
    File.write file, item(id, **opts).to_yaml
    file
  end

  it "writes a record that is not published yet" do
    stats = described_class.write_all [item("ITU-R BO.9999-0", date: "2026-01-01")], fetcher

    expect(stats[:added]).to eq 1
    expect(File).to exist("data/itu-r-bo-9999-0.yaml")
  end

  # The crawl sees a recommendation's *approval* date; the published record holds
  # the *publication* date RunSearch served. Overwriting it would rewrite the year
  # on ~60% of ITU-R records and change which edition answers a dated reference.
  it "never rewrites a published date" do
    file = publish "ITU-R BO.600-1", date: "2002-01", source: "https://itu.int/x.pdf"
    stats = described_class.write_all [item("ITU-R BO.600-1", date: "1986-07-01")], fetcher

    expect(stats[:unchanged]).to eq 1
    expect(Relaton::Itu::Item.from_yaml(File.read(file)).date.first.at.to_s).to eq "2002-01"
  end

  it "backfills a source the published record lacks, keeping its date" do
    file = publish "ITU-R BO.600-1", date: "2002-01"
    pdf = "https://www.itu.int/dms_pubrec/itu-r/rec/bo/R-REC-BO.600-1-198607-I!!PDF-E.pdf"

    stats = described_class.write_all [item("ITU-R BO.600-1", date: "1986-07-01", source: pdf)], fetcher

    expect(stats[:backfilled]).to eq 1
    merged = Relaton::Itu::Item.from_yaml File.read(file)
    expect(merged.source.first.content.to_s).to eq pdf
    expect(merged.date.first.at.to_s).to eq "2002-01"
  end

  it "leaves an unchanged record byte-identical but still indexes it" do
    file = publish "ITU-R BO.600-1", date: "2002-01", source: "https://itu.int/x.pdf"
    before = File.read file
    expect(fetcher).to receive(:index_primary).with("ITU-R BO.600-1", file)

    stats = described_class.write_all [item("ITU-R BO.600-1", date: "1986-07-01", source: "https://itu.int/y.pdf")], fetcher

    expect(stats[:unchanged]).to eq 1
    expect(File.read(file)).to eq before
  end

  # A report and a recommendation in the same series can carry the same
  # docidentifier, and therefore the same filename. Silently overwriting would
  # delete one of them from the dataset.
  it "refuses to overwrite a record of a different doctype" do
    file = publish "ITU-R BO.1227-1", doctype: "technical-report", date: "1994-01"
    before = File.read file

    stats = nil
    expect { stats = described_class.write_all [item("ITU-R BO.1227-1", doctype: "recommendation")], fetcher }
      .to output(/collision/i).to_stderr_from_any_process

    expect(stats[:collisions])
      .to eq [["data/itu-r-bo-1227-1.yaml", "ITU-R BO.1227-1 (technical-report)",
               "ITU-R BO.1227-1 (recommendation)"]]
    expect(stats[:skipped]).to eq 1
    expect(File.read(file)).to eq before
  end

  # output_file collapses ".", "/" and spaces alike, so two distinct docids can
  # claim one filename even within a single doctype.
  it "refuses to overwrite a record whose docid merely sanitizes the same" do
    file = publish "ITU-R BO.4/BL/4"
    before = File.read file

    stats = nil
    expect { stats = described_class.write_all [item("ITU-R BO.4-BL-4")], fetcher }
      .to output(/collision/i).to_stderr_from_any_process

    expect(stats[:collisions].first).to eq [file, "ITU-R BO.4/BL/4 (recommendation)",
                                            "ITU-R BO.4-BL-4 (recommendation)"]
    expect(File.read(file)).to eq before
  end

  it "skips an unreadable published record without losing the rest of the harvest" do
    File.write "data/itu-r-bo-600-1.yaml", "not: [a, record"
    stats = nil

    expect do
      stats = described_class.write_all(
        [item("ITU-R BO.600-1", date: "1986-07"), item("ITU-R BO.9999-0", date: "2026-01")], fetcher
      )
    end.to output(/skipped/).to_stderr_from_any_process

    expect(stats[:skipped]).to eq 1
    expect(stats[:added]).to eq 1
    expect(File).to exist("data/itu-r-bo-9999-0.yaml")
  end

  # The backfill path round-trips the published record through
  # Item.from_yaml -> to_yaml; the spec's own helper can't prove that keeps
  # fields it doesn't know about (id, schema_version), so use a real record.
  context "with a real published record" do
    let(:published) { File.read File.join(__dir__, "..", "..", "fixtures", "published-itu-r-bo-600-1.yaml") }

    before { File.write "data/itu-r-bo-600-1.yaml", published }

    it "leaves it byte-identical when there is nothing to backfill" do
      stats = described_class.write_all [item("ITU-R BO.600-1", date: "1986-07", source: nil)], fetcher

      expect(stats[:unchanged]).to eq 1
      expect(File.read("data/itu-r-bo-600-1.yaml")).to eq published
    end

    it "keeps its id, schema_version and date when backfilling a source" do
      pdf = "https://www.itu.int/dms_pubrec/itu-r/rec/bo/R-REC-BO.600-1-198607-I!!PDF-E.pdf"
      described_class.write_all [item("ITU-R BO.600-1", date: "1986-07", source: pdf)], fetcher

      merged = YAML.safe_load_file "data/itu-r-bo-600-1.yaml", permitted_classes: [Date, Time]
      original = YAML.safe_load published, permitted_classes: [Date, Time]
      expect(merged["source"].first["content"]).to eq pdf
      expect(merged.reject { |k, _| k == "source" }).to eq original.reject { |k, _| k == "source" }
    end
  end

  it "reports two harvested records that claim one filename" do
    stats = nil
    expect do
      stats = described_class.write_all(
        [item("ITU-R BO.1227-1", doctype: "recommendation"),
         item("ITU-R BO.1227-1", doctype: "technical-report")], fetcher
      )
    end.to output(/collision/i).to_stderr_from_any_process

    expect(stats[:added]).to eq 1
    expect(stats[:collisions].size).to eq 1
  end

  it "skips a record with no primary docidentifier instead of crashing" do
    bib = Relaton::Itu::ItemData.new(
      docidentifier: [], title: [], date: [], source: [], language: ["en"], script: ["Latn"],
      type: "standard", ext: Relaton::Itu::Ext.new(doctype: Relaton::Itu::Doctype.new(content: "recommendation")),
    )
    expect { described_class.write_all([bib], fetcher) }.not_to raise_error
  end
end
