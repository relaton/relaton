# encoding: UTF-8

require "relaton/cie/data_fetcher"

# relaton-cie#13: a translation (`CIE 232:2019(DE)`) has the same primary id
# as its English document, so it must merge into the English record instead
# of overwriting it.
RSpec.describe Relaton::Cie::DataFetcher, "translations" do
  subject { described_class.new "data", "yaml" }

  let(:en_url) { "https://store.accuristech.com/standards/cie-232-2019?product_id=2074145" }
  let(:de_url) { "https://store.accuristech.com/standards/cie-232-2019-de?product_id=2247892" }

  def hit_for(url, code)
    Nokogiri::HTML(<<~HTML).at_xpath("//li")
      <li data-product="1"><div class="product_detail"><h3>
        <a href="#{url}">#{code}<span class="ss-icon">▹</span></a>
      </h3></div></li>
    HTML
  end

  def item_for(url, title, lang)
    Relaton::Cie::ItemData.new(
      docidentifier: [Relaton::Bib::Docidentifier.new(type: "CIE", content: "CIE 232:2019", primary: true)],
      title: Relaton::Bib::Title.from_string(title, lang == "en" ? nil : lang),
      abstract: [Relaton::Bib::Abstract.new(content: "Abstract #{lang}", language: lang, script: "Latn")],
      source: [Relaton::Bib::Uri.new(type: "src", content: url)],
      language: [lang], script: ["Latn"]
    )
  end

  describe "#translation_language" do
    it "reads a non-English language slug from the URL" do
      expect(subject.translation_language(hit_for(de_url, "CIE 232:2019"))).to eq "de"
    end

    it "answers nil for an English slug" do
      url = "https://store.accuristech.com/standards/cie-iso-8995-1-2025-en?product_id=2930375"
      expect(subject.translation_language(hit_for(url, "CIE ISO 8995-1:2025(en)"))).to be_nil
    end

    it "answers nil when the URL has no language slug" do
      expect(subject.translation_language(hit_for(en_url, "CIE 232:2019"))).to be_nil
    end

    it "answers nil for a 2-letter slug that is not a language" do
      url = "https://store.accuristech.com/standards/cie-x051-2025-xy?product_id=3"
      expect(subject.translation_language(hit_for(url, "CIE x051:2025"))).to be_nil
    end

    it "falls back to a language suffix in the code" do
      url = "https://www.techstreet.com/cie/standards/cie-232-2019?product_id=2247892"
      expect(subject.translation_language(hit_for(url, "CIE 232:2019(DE)"))).to eq "de"
    end

    it "ignores a 2-letter group in the code that is not the last token" do
      url = "https://www.techstreet.com/cie/standards/cie-x?product_id=1"
      expect(subject.translation_language(hit_for(url, "CIE (IT) lighting 2019"))).to be_nil
    end
  end

  describe "script of a translation" do
    it "is Cyrl for Russian and Latn for German" do
      expect(subject.script_for("ru")).to eq "Cyrl"
      expect(subject.script_for("de")).to eq "Latn"
      expect(subject.script_for(nil)).to eq "Latn"
    end
  end

  describe "#parse_page with a translation hit" do
    let(:doc) { Nokogiri::HTML File.read("fixtures/doc.html") }
    let(:agent) { instance_double(Relaton::Cie::BrowserAgent, quit: nil) }

    before do
      allow(subject).to receive(:agent).and_return(agent)
      allow(subject).to receive(:time_req).and_yield
      allow(agent).to receive(:get).with(de_url).and_return doc
    end

    it "builds a German item and defers it instead of writing it" do
      expect(subject).not_to receive(:write_file)
      subject.parse_page hit_for(de_url, "CIE 232:2019(DE)"), 7
      deferred = subject.instance_variable_get(:@translations)["data/cie-232-2019.yaml"]
      expect(deferred.size).to eq 1
      pos, item = deferred.first
      expect(pos).to eq 7
      expect(item.language).to eq ["de"]
      expect(item.title.map(&:language).uniq).to eq ["de"]
      expect(item.abstract.map(&:language)).to eq ["de"]
      expect(item.docidentifier.first.content).to eq "CIE 232:2019"
    end
  end

  describe "#merge_translations" do
    before { allow(subject.index).to receive(:add_or_update) }

    def written
      out = {}
      allow(subject).to receive(:serialize) { |bib| bib }
      allow(File).to receive(:write) { |file, bib, **| out[file] = bib }
      out
    end

    def relations_of(bib)
      bib.relation.select { |r| r.type == "hasTranslation" }
    end

    it "links a translation to the English record with hasTranslation" do
      out = written
      base = item_for(en_url, "Discomfort glare", "en")
      base.docidentifier << Relaton::Bib::Docidentifier.new(type: "ISBN", content: "9783902842152")
      trans = item_for(de_url, "Psychologische Blendung", "de")
      trans.docidentifier << Relaton::Bib::Docidentifier.new(type: "ISBN", content: "9783902842886")
      trans.date = [Relaton::Bib::Date.new(type: "published", at: "2022-02-01")]
      subject.write_file base, 0
      subject.instance_variable_get(:@translations)["data/cie-232-2019.yaml"] << [3, trans]
      subject.merge_translations

      bib = out["data/cie-232-2019.yaml"]
      # The English record keeps its own identity.
      expect(bib.language).to eq ["en"]
      expect(bib.source.map(&:content)).to eq [en_url]
      expect(bib.abstract.map(&:language)).to eq ["en"]
      expect(bib.docidentifier.map(&:content)).to eq ["CIE 232:2019", "9783902842152"]
      # Only the translated title joins it, tagged with its language.
      de_titles = bib.title.select { |t| t.content == "Psychologische Blendung" }
      expect(de_titles.map(&:language).uniq).to eq ["de"]
      # The translation is its own publication in the relation.
      rels = relations_of(bib)
      expect(rels.size).to eq 1
      rel = rels.first.bibitem
      expect(rel.docidentifier.map(&:content)).to eq ["CIE 232:2019", "9783902842886"]
      expect(rel.date.map(&:at).map(&:to_s)).to eq ["2022-02-01"]
      expect(rel.source.map(&:content)).to eq [de_url]
      expect(rel.language).to eq ["de"]
      expect(rel.title.map(&:language).uniq).to eq ["de"]
      expect(rel.abstract).to be_empty
    end

    it "is idempotent for a translation that repeats" do
      out = written
      subject.write_file item_for(en_url, "Discomfort glare", "en"), 0
      2.times do |i|
        subject.instance_variable_get(:@translations)["data/cie-232-2019.yaml"] <<
          [3 + i, item_for(de_url, "Psychologische Blendung", "de")]
      end
      subject.merge_translations
      bib = out["data/cie-232-2019.yaml"]
      expect(relations_of(bib).size).to eq 1
      expect(bib.title.count { |t| t.content == "Psychologische Blendung" }).to eq 2 # title-main + main
    end

    it "adds several translations in catalogue order" do
      out = written
      fr_url = "https://store.accuristech.com/standards/cie-232-2019-fr?product_id=9"
      subject.write_file item_for(en_url, "Discomfort glare", "en"), 0
      list = subject.instance_variable_get(:@translations)["data/cie-232-2019.yaml"]
      list << [5, item_for(fr_url, "Éblouissement", "fr")]
      list << [2, item_for(de_url, "Psychologische Blendung", "de")]
      subject.merge_translations
      langs = relations_of(out["data/cie-232-2019.yaml"]).map { |r| r.bibitem.language }
      expect(langs).to eq [["de"], ["fr"]]
    end

    it "keeps the English record's other relations" do
      out = written
      base = item_for(en_url, "Discomfort glare", "en")
      old = Relaton::Cie::ItemData.new(
        docidentifier: [Relaton::Bib::Docidentifier.new(type: "CIE", content: "CIE 117-1995", primary: true)],
      )
      base.relation = [Relaton::Bib::Relation.new(type: "updates", bibitem: old)]
      subject.write_file base, 0
      subject.instance_variable_get(:@translations)["data/cie-232-2019.yaml"] <<
        [3, item_for(de_url, "Psychologische Blendung", "de")]
      subject.merge_translations
      expect(out["data/cie-232-2019.yaml"].relation.map(&:type)).to eq %w[updates hasTranslation]
    end

    it "logs a failure for one file and still merges the others" do
      out = written
      subject.instance_variable_get(:@translations)["data/a.yaml"] << [1, item_for(de_url, "A", "de")]
      subject.instance_variable_get(:@translations)["data/cie-232-2019.yaml"] <<
        [3, item_for(de_url, "Psychologische Blendung", "de")]
      allow(subject).to receive(:output_file).and_call_original
      call = 0
      allow(subject).to receive(:write_file).and_wrap_original do |m, *args|
        call += 1
        raise "boom" if call == 1

        m.call(*args)
      end
      expect { subject.merge_translations }.to output(/boom/).to_stderr_from_any_process
      expect(out).to have_key "data/cie-232-2019.yaml"
    end

    it "writes a translation alone when the catalogue has no English record" do
      out = written
      subject.instance_variable_get(:@translations)["data/cie-232-2019.yaml"] <<
        [3, item_for(de_url, "Psychologische Blendung", "de")]
      subject.merge_translations
      expect(out["data/cie-232-2019.yaml"].language).to eq ["de"]
      expect(subject.index).to have_received(:add_or_update)
        .with(satisfy { |id| id.to_s == "CIE 232:2019" }, "data/cie-232-2019.yaml")
    end
  end

  describe "#fetch" do
    it "merges translations before it saves the index" do
      allow(subject).to receive(:collect_hits).and_return []
      expect(subject).to receive(:merge_translations).ordered
      expect(subject.index).to receive(:save).ordered
      allow(subject).to receive(:report_errors)
      subject.fetch
    end
  end
end
