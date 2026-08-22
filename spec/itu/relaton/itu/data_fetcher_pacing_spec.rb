require "relaton/itu/data_fetcher"
require "relaton/itu/data_crawler_r"
require "tmpdir"
require "fileutils"

# Everything added to keep the relaton-data-itu crawl under GitHub Actions' 6 h
# per-job cap (run 32420518511 was cancelled at 6h00m19s). Kept in its own file
# rather than nested inside data_fetcher_spec.rb, whose contexts run under a
# shared VCR/webmock setup this needs none of.
RSpec.describe Relaton::Itu::DataFetcher do
  def with_env(name, value)
    was = ENV[name]
    ENV[name] = value
    yield
  ensure
    ENV[name] = was
  end

  describe "crawl pacing knobs" do
    it "defaults the ITU-R pool and honours its own env var" do
      with_env("RELATON_ITU_R_CONCURRENCY", nil) do
        expect(described_class.r_concurrency).to eq described_class::DEFAULT_R_CONCURRENCY
      end
      with_env("RELATON_ITU_R_CONCURRENCY", "2") { expect(described_class.r_concurrency).to eq 2 }
      with_env("RELATON_ITU_R_CONCURRENCY", "0") { expect(described_class.r_concurrency).to eq 1 }
    end

    it "keeps the ITU-R pool separate from the ITU-T pool" do
      # The two halves have different bottlenecks — ITU-T is latency-bound,
      # ITU-R is pacer-bound — so one knob for both would be wrong.
      with_env("RELATON_ITU_CONCURRENCY", "16") do
        expect(described_class.r_concurrency).to eq described_class::DEFAULT_R_CONCURRENCY
      end
    end

    it "paces by slot unless asked for the legacy fixed sleep" do
      with_env("RELATON_ITU_PACE", nil) { expect(described_class.pace_mode).to eq :slot }
      with_env("RELATON_ITU_PACE", "fixed") { expect(described_class.pace_mode).to eq :fixed }
      with_env("RELATON_ITU_PACE", "slot") { expect(described_class.pace_mode).to eq :slot }
    end

    it "builds the crawler with the pool and pacing the environment asks for" do
      # The rollback recipe has to actually reach the crawler.
      fetcher = described_class.new Dir.mktmpdir, "yaml"
      crawler = double "crawler", series: [], throttle_count: 0, abandoned?: false, shutdown: nil
      with_env("RELATON_ITU_R_CONCURRENCY", "3") do
        with_env("RELATON_ITU_PACE", "fixed") do
          expect(Relaton::Itu::DataCrawlerR).to receive(:new)
            .with(hash_including(concurrency: 3, pace_mode: :fixed)).and_return crawler
          fetcher.fetch_publications
        end
      end
    end

    it "gives the ITU-T crawl a real cache, and an off switch" do
      with_env("RELATON_ITU_CACHE_ENTRIES", nil) do
        expect(described_class.family_cache).to be_a Relaton::Itu::FamilyCache
      end
      with_env("RELATON_ITU_CACHE_ENTRIES", "0") do
        expect(described_class.family_cache).to be_a Relaton::Itu::NullCache
      end
      with_env("RELATON_ITU_CACHE_ENTRIES", "7") do
        expect(described_class.family_cache).to be_a Relaton::Itu::FamilyCache
      end
    end
  end

  describe ".family_key" do
    def key(name)
      described_class.family_key("rec_name" => name)
    end

    it("drops the edition date") { expect(key("H.264 (06/2026)")).to eq "H.264" }
    it("drops a version marker too") { expect(key("H.264 (V16) (06/2026)")).to eq "H.264" }
    it("keeps a supplement distinct") { expect(key("H Suppl. 1 (05/1999)")).to eq "H Suppl. 1" }
    it("canonicalises the space spelling") { expect(key("G 231 (10/1976)")).to eq "G.231" }
    it("survives a row with no name") { expect(key(nil)).to eq "" }
  end

  describe ".group_by_family" do
    let(:work) do
      [[{ "rec_name" => "H.264 (06/2026)" }, 0],
       [{ "rec_name" => "G.711 (11/1988)" }, 1],
       [{ "rec_name" => "H.264 (05/2003)" }, 2]]
    end

    it "makes a family's rows contiguous, so its cache entry is still resident" do
      names = described_class.group_by_family(work).map { |row, _| described_class.family_key(row) }
      expect(names).to eq %w[H.264 H.264 G.711]
    end

    it "carries every [row, pos] pair through untouched" do
      # `pos` is the searchRecs position and keeps that meaning: it is what
      # #write_file's max-by-position rule uses to pick a deterministic winner
      # for two docids that sanitize to one filename. Reordering the enqueue is
      # indistinguishable, to that rule, from a different worker completion
      # order — which it already tolerates.
      grouped = described_class.group_by_family(work)
      expect(grouped.map(&:last).sort).to eq [0, 1, 2]
      expect(grouped.sort_by(&:last)).to eq work
    end
  end

  describe "ITU-T top-up" do
    subject(:fetcher) { described_class.new dir, "yaml" }

    let(:dir) { Dir.mktmpdir }
    after { FileUtils.rm_rf dir }

    describe "#held_t?" do
      it "answers from disk alone, with no HTTP at all" do
        # This is what makes an ITU-T top-up cheap: the decision happens before
        # any of the four detail requests. DataParserT.fetch_docid reads only
        # rec_name and does no I/O.
        row = { "rec_name" => "H.264 (06/2026)" }
        expect_any_instance_of(Mechanize).not_to receive(:get)
        expect(fetcher.held_t?(row)).to be_falsey

        FileUtils.touch fetcher.output_file("ITU-T H.264 (06/2026)")
        expect(fetcher.held_t?(row)).to be true
      end

      it "derives the same filename #write_file would" do
        FileUtils.touch fetcher.output_file("ITU-T G.231 (10/1976)")
        expect(fetcher.held_t?("rec_name" => "G 231 (10/1976)")).to be true
      end

      it "is false for a row with no usable name" do
        expect(fetcher.held_t?("rec_name" => "")).to be_falsey
      end
    end

    describe "#top_up_rows" do
      let(:work) do
        [[{ "rec_name" => "H.264 (05/2003)" }, 0],   # held
         [{ "rec_name" => "H.264 (06/2026)" }, 1],   # new  -> family re-harvested
         [{ "rec_name" => "G.711 (11/1988)" }, 2]]   # held -> family skipped
      end

      before do
        FileUtils.touch fetcher.output_file("ITU-T H.264 (05/2003)")
        FileUtils.touch fetcher.output_file("ITU-T G.711 (11/1988)")
      end

      it "re-harvests a whole family when any of its editions is new" do
        # Not just the new row: a new edition changes its siblings' hasEdition
        # relations, so a row-wise top-up would leave them stale on disk.
        expect(fetcher.top_up_rows(work).map(&:last)).to contain_exactly 0, 1
      end

      it "drops a family the dataset already holds entirely" do
        expect(fetcher.top_up_rows(work).map { |row, _| row["rec_name"] })
          .not_to include "G.711 (11/1988)"
      end

      it "keeps everything when nothing is held" do
        FileUtils.rm_f Dir["#{dir}/*.yaml"]
        expect(fetcher.top_up_rows(work).size).to eq 3
      end
    end
  end
  describe "#fetch_recommendations" do
    subject(:fetcher) { described_class.new Dir.mktmpdir, "yaml" }

    let(:rows) do
      [{ "rec_name" => "H.264 (06/2026)", "idrec" => 1 },
       { "rec_name" => "G.711 (11/1988)", "idrec" => 2 }]
    end

    before do
      allow(fetcher).to receive(:search_recs).and_return rows
      allow(fetcher).to receive(:rec_agent).and_return instance_double(Mechanize, shutdown: nil)
      allow(Relaton::Itu::DataParserT).to receive(:parse).and_return nil
    end

    it "shares ONE cache across the whole worker pool" do
      # A per-worker cache would still issue one getRecEditions per worker, and
      # with eight workers that is most of the de-duplication gone.
      seen = Queue.new
      allow(Relaton::Itu::DataParserT).to receive(:parse) do |_row, _agent, _errors, cache:|
        seen << cache.object_id
        nil
      end
      fetcher.fetch_recommendations
      ids = []
      ids << seen.pop until seen.empty?
      expect(ids.uniq.size).to eq 1
    end

    it "enriches every row on a full run" do
      expect(Relaton::Itu::DataParserT).to receive(:parse).twice.and_return nil
      fetcher.fetch_recommendations mode: :full
    end

    it "skips a family the dataset already holds when topping up" do
      FileUtils.touch fetcher.output_file("ITU-T G.711 (11/1988)")
      parsed = Queue.new
      allow(Relaton::Itu::DataParserT).to receive(:parse) do |row, *|
        parsed << row["rec_name"]
        nil
      end
      fetcher.fetch_recommendations mode: :top_up
      names = []
      names << parsed.pop until parsed.empty?
      expect(names).to eq ["H.264 (06/2026)"]
    end
  end
end
