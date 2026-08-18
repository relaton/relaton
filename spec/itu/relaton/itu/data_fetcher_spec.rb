require "relaton/itu/data_crawler_r"
require "relaton/itu/data_merge_r"
require "relaton/itu/data_fetcher"

describe Relaton::Itu::DataFetcher do
  # Run a block with RELATON_ITU_CONCURRENCY set (nil = unset), restoring it
  # afterwards so worker-pool size never leaks between examples.
  def with_concurrency(value)
    was = ENV["RELATON_ITU_CONCURRENCY"]
    ENV["RELATON_ITU_CONCURRENCY"] = value
    yield
  ensure
    ENV["RELATON_ITU_CONCURRENCY"] = was
  end

  it "::fetch" do
    expect(FileUtils).to receive(:mkdir_p).with("data")
    df = double "df"
    expect(df).to receive(:fetch).with(nil)
    expect(described_class).to receive(:new).with("data", "yaml").and_return df
    described_class.fetch
  end

  context "instance methods" do
    let(:bib) do
      Relaton::Itu::ItemData.new(
        docidentifier: [Relaton::Itu::Docidentifier.new(type: "ITU", content: "ITU-R M.1234", primary: true)],
        title: [Relaton::Bib::Title.new(type: "main", content: "Test title", language: "en", script: "Latn")],
        language: ["en"], script: ["Latn"], type: "standard",
        ext: Relaton::Itu::Ext.new(doctype: Relaton::Itu::Doctype.new(content: "recommendation")),
      )
    end

    subject { described_class.new "data", "yaml" }

    it("#index") { expect(subject.index).to be_instance_of Relaton::Index::Type }

    context "#fetch itu-r routing" do
      # The ITU-R harvester is back (issue #75): enumeration now walks the
      # /pub + /rec pages ITU still renders, and the result is *merged* rather
      # than written as a rebuild, because the crawl sees less than the
      # preserved dataset holds.
      before do
        allow(subject).to receive(:migrate_report_ids)
        allow(subject.index).to receive(:save)
      end

      [nil, "itu-r"].each do |source|
        it "harvests every family for source #{source.inspect}" do
          crawler = double "crawler"
          allow(Relaton::Itu::DataCrawlerR).to receive(:new).and_return crawler
          allow(crawler).to receive(:series).with("R-REC").and_return %w[BO]
          allow(crawler).to receive(:series).with("R-REP").and_return %w[BT]
          expect(crawler).to receive(:harvest).with("BO", hash_including(family: "R-REC")).and_return [:rec]
          expect(crawler).to receive(:harvest).with("BT", hash_including(family: "R-REP")).and_return [:rep]
          expect(Relaton::Itu::DataMergeR).to receive(:write_all).twice
            .and_return({ added: 1, backfilled: 0, unchanged: 0, skipped: 0, collisions: [] })

          subject.fetch source
        end
      end

      it "tallies the merge across families" do
        crawler = double "crawler", series: %w[BO]
        allow(Relaton::Itu::DataCrawlerR).to receive(:new).and_return crawler
        allow(crawler).to receive(:harvest).and_return [:item]
        allow(Relaton::Itu::DataMergeR).to receive(:write_all)
          .and_return({ added: 1, backfilled: 2, unchanged: 3, skipped: 0, collisions: [] })

        # one series per family, so every count doubles
        expect(subject.fetch_publications).to include added: 2, backfilled: 4, unchanged: 6
      end

      it "migrates the Report docids before harvesting, so nothing is added twice" do
        # A Report's docid now leads with "Report " (#110). Harvesting before the
        # published records are rewritten would add a second copy of each one.
        allow(subject).to receive(:migrate_report_ids).and_call_original
        expect(subject).to receive(:migrate_report_ids).ordered
        expect(Relaton::Itu::DataCrawlerR).to receive(:new).ordered.and_return double("c", series: [])

        subject.fetch "itu-r"
      end

      it "loses only the series that fails, not the run" do
        crawler = double "crawler"
        allow(Relaton::Itu::DataCrawlerR).to receive(:new).and_return crawler
        allow(crawler).to receive(:series).and_return %w[BO BT]
        allow(crawler).to receive(:harvest).with("BO", anything).and_raise Relaton::RequestError, "throttled"
        allow(crawler).to receive(:harvest).with("BT", anything).and_return []
        allow(Relaton::Itu::DataMergeR).to receive(:write_all).and_return({})

        expect { subject.fetch "itu-r" }.to output(/BO skipped: throttled/).to_stderr_from_any_process
      end
    end

    context "#migrate_report_ids" do
      def write(dir, name, id, doctype)
        item = Relaton::Itu::ItemData.new(
          docidentifier: [Relaton::Itu::Docidentifier.new(type: "ITU", content: id, primary: true)],
          title: [Relaton::Bib::Title.new(type: "main", content: "T", language: "en", script: "Latn")],
          language: ["en"], script: ["Latn"], type: "standard",
          ext: Relaton::Itu::Ext.new(doctype: Relaton::Itu::Doctype.new(content: doctype), flavor: "itu"),
        )
        File.write File.join(dir, name), item.to_yaml
      end

      it "rewrites Reports onto their Report docid and leaves Recommendations alone" do
        Dir.mktmpdir do |dir|
          write dir, "itu-r-bt-2020-1.yaml", "ITU-R BT.2020-1", "technical-report"
          write dir, "itu-r-bo-1130-5.yaml", "ITU-R BO.1130-5", "recommendation"
          fetcher = described_class.new dir, "yaml"
          allow(fetcher).to receive(:index).and_return double("index", add_or_update: nil)

          expect(fetcher.migrate_report_ids("#{dir}/itu-r-*.yaml")).to eq 1

          moved = File.join dir, "report-itu-r-bt-2020-1.yaml"
          expect(File).to exist(moved)
          expect(File).not_to exist(File.join(dir, "itu-r-bt-2020-1.yaml"))
          expect(Relaton::Itu::Item.from_yaml(File.read(moved)).docidentifier.first.content)
            .to eq "Report ITU-R BT.2020-1"
          expect(File).to exist(File.join(dir, "itu-r-bo-1130-5.yaml")) # untouched
        end
      end

      it "is idempotent, so a second crawl does not re-prefix" do
        Dir.mktmpdir do |dir|
          write dir, "report-itu-r-bt-2020-1.yaml", "Report ITU-R BT.2020-1", "technical-report"
          fetcher = described_class.new dir, "yaml"

          expect(fetcher.migrate_report_ids("#{dir}/*.yaml")).to eq 0
          expect(Relaton::Itu::Item.from_yaml(File.read("#{dir}/report-itu-r-bt-2020-1.yaml"))
            .docidentifier.first.content).to eq "Report ITU-R BT.2020-1"
        end
      end
    end

    context "#fetch itu-t routing" do
      # One worker keeps the expectations order-independent; the pool itself is
      # exercised in "#fetch_recommendations concurrency" below.
      around { |ex| with_concurrency("1") { ex.run } }

      it "harvests recommendations via search_recs for the itu-t source" do
        bib = double "bib", contributor: [double("publisher")]
        agent = double "agent", shutdown: nil
        row1 = { "rec_name" => "A.1 (10/2000)" }
        row2 = { "rec_name" => "A.2 (11/2006)" }

        allow(subject).to receive(:rec_agent).and_return agent
        expect(subject).to receive(:search_recs).and_return [row1, row2]
        expect(Relaton::Itu::DataParserT).to receive(:parse).with(row1, agent, kind_of(Hash)).and_return bib
        expect(Relaton::Itu::DataParserT).to receive(:parse).with(row2, agent, kind_of(Hash)).and_return nil
        expect(subject).to receive(:write_file).with(bib, 0).once
        expect(subject.index).to receive(:save)

        subject.fetch("itu-t")
      end

      it "reports records whose enrichment degraded them to the thin shape" do
        thin = double "bib", contributor: []
        agent = double "agent", shutdown: nil

        allow(subject).to receive(:rec_agent).and_return agent
        allow(subject).to receive(:write_file)
        allow(subject.index).to receive(:save)
        expect(subject).to receive(:search_recs).and_return [{ "rec_name" => "A.1 (10/2000)" }]
        expect(Relaton::Itu::DataParserT).to receive(:parse).and_return thin

        expect { subject.fetch("itu-t") }
          .to output(/enrichment failed for 1\/1 records/).to_stderr_from_any_process
      end
    end

    context "#fetch_recommendations concurrency" do
      it "defaults to DEFAULT_CONCURRENCY and honours the env var" do
        with_concurrency(nil) { expect(described_class.concurrency).to eq described_class::DEFAULT_CONCURRENCY }
        with_concurrency("3") { expect(described_class.concurrency).to eq 3 }
        with_concurrency("0") { expect(described_class.concurrency).to eq 1 }
      end

      it "gives every worker its own agent and shuts them all down" do
        agents = Array.new(3) { |i| double("agent#{i}", shutdown: nil) }
        agents.each { |a| expect(a).to receive(:shutdown) }

        with_concurrency("3") do
          expect(subject).to receive(:rec_agent).and_return(*agents)
          expect(subject).to receive(:search_recs).and_return []
          subject.fetch_recommendations
        end
      end

      it "parses every row exactly once across the pool" do
        rows = Array.new(50) { |i| { "rec_name" => "A.#{i} (10/2000)" } }
        parsed = Queue.new

        with_concurrency("4") do
          allow(subject).to receive(:rec_agent) { double("agent", shutdown: nil) }
          expect(subject).to receive(:search_recs).and_return rows
          allow(Relaton::Itu::DataParserT).to receive(:parse) { |row, *| parsed << row; nil }
          subject.fetch_recommendations
        end

        expect(Array.new(parsed.size) { parsed.pop }).to match_array(rows)
      end
    end

    context "#index_files" do
      def write_record(dir, name, id)
        item = Relaton::Itu::ItemData.new(
          docidentifier: [Relaton::Itu::Docidentifier.new(type: "ITU", content: id, primary: true)],
          title: [Relaton::Bib::Title.new(type: "main", content: "T", language: "en", script: "Latn")],
          language: ["en"], script: ["Latn"], type: "standard",
          ext: Relaton::Itu::Ext.new(doctype: Relaton::Itu::Doctype.new(content: "recommendation")),
        )
        File.join(dir, name).tap { |f| File.write f, item.to_yaml }
      end

      it "indexes records already on disk and reports the ids it can't parse" do
        Dir.mktmpdir do |dir|
          good = write_record dir, "itu-r-bo-600-1.yaml", "ITU-R BO.600-1"
          bad = write_record dir, "itu-r-rr.yaml", "ITU-R RR"
          index = double "index"
          allow(subject).to receive(:index).and_return index
          expect(index).to receive(:add_or_update).with(kind_of(::Pubid::Itu::Identifier), good).once

          expect(subject.index_files("#{dir}/*.yaml")).to eq 1
          expect(subject.unparseable_ids).to eq [["ITU-R RR", bad]]
        end
      end

      it "logs and skips a file it cannot read as a record" do
        Dir.mktmpdir do |dir|
          File.write File.join(dir, "broken.yaml"), "not: [a, record"
          expect { expect(subject.index_files("#{dir}/*.yaml")).to eq 0 }
            .to output(/Failed to index/).to_stderr_from_any_process
        end
      end
    end

    context "#search_recs" do
      it "sends a GET to the searchRecs endpoint and returns Data" do
        response = double "response", body: '{"Total":1,"Data":[{"rec_name":"A.1 (10/2000)"}]}'
        http = double "http"
        expect(Net::HTTP).to receive(:new).with("www.itu.int", 443).and_return http
        expect(http).to receive(:use_ssl=).with(true)
        expect(http).to receive(:request) do |req|
          expect(req).to be_instance_of Net::HTTP::Get
          expect(req.path).to include "/mws/api/recommendations/searchRecs"
          expect(req.path).to include "main_edition_flag=0"
          expect(req["Accept"]).to eq "application/json"
          expect(req["User-Agent"]).to start_with "Mozilla/5.0"
          response
        end

        expect(subject.send(:search_recs)).to eq [{ "rec_name" => "A.1 (10/2000)" }]
      end

      it "returns empty array when no Data key" do
        response = double "response", body: "{}"
        http = double "http"
        expect(Net::HTTP).to receive(:new).and_return http
        expect(http).to receive(:use_ssl=)
        expect(http).to receive(:request).and_return response

        expect(subject.send(:search_recs)).to eq []
      end
    end

    context "#write_file" do
      before do
        expect(subject).to receive(:serialize).with(bib).and_return :content
        expect(File).to receive(:write).with("data/itu-r-m-1234.yaml", :content, encoding: "UTF-8")
      end

      it "writes the file and indexes the primary id" do
        expect(subject).to receive(:index_primary).with("ITU-R M.1234", "data/itu-r-m-1234.yaml")
        subject.write_file bib
        expect(subject.instance_variable_get(:@files)).to eq Set["data/itu-r-m-1234.yaml"]
      end

      it "file exists" do
        allow(subject).to receive(:index_primary)
        subject.instance_variable_set :@files, Set["data/itu-r-m-1234.yaml"]
        expect do
          subject.write_file bib
        end.to output(/File data\/itu-r-m-1234\.yaml exists./).to_stderr_from_any_process
      end
    end

    context "#index_primary (unparseable id handling, mirrors ISO)" do
      let(:index_double) { double("index") }

      before { allow(subject).to receive(:index).and_return(index_double) }

      it "indexes the parsed pubid" do
        expect(index_double).to receive(:add_or_update)
          .with(kind_of(::Pubid::Itu::Identifier), "data/itu-r-bo-600-1.yaml")
        subject.send(:index_primary, "ITU-R BO.600-1", "data/itu-r-bo-600-1.yaml")
        expect(subject.send(:unparseable_ids)).to be_empty
      end

      it "indexes a dated ITU-T recommendation id per edition" do
        expect(index_double).to receive(:add_or_update)
          .with(kind_of(::Pubid::Itu::Identifier), "data/itu-t-a-1-10-2000.yaml")
        subject.send(:index_primary, "ITU-T A.1 (10/2000)", "data/itu-t-a-1-10-2000.yaml")
        expect(subject.send(:unparseable_ids)).to be_empty
      end

      it "records an unparseable id instead of indexing a raw string" do
        # ITU-R RR (Radio Regulations) is not modelled by pubid, so it must be
        # recorded (and surfaced as a GitHub issue) rather than corrupt the index.
        expect(index_double).not_to receive(:add_or_update)
        subject.send(:index_primary, "ITU-R RR", "data/itu-r-rr.yaml")
        expect(subject.send(:unparseable_ids))
          .to eq([["ITU-R RR", "data/itu-r-rr.yaml"]])
      end

      it "reports recorded unparseable ids through the error machinery" do
        subject.send(:unparseable_ids) << ["ITU-R RR", "f.yaml"]
        allow(subject).to receive(:gh_issue)
        allow(subject).to receive(:log_error)
        subject.send(:report_errors)
        expect(subject).to have_received(:log_error)
          .with(%r{Unparseable primary id `ITU-R RR`.*f\.yaml})
      end
    end

    context "serialization" do
      it("#to_yaml") { expect(subject.to_yaml(bib)).to be_instance_of String }
      it("#to_xml") { expect(subject.to_xml(bib)).to include("<bibdata") }
      it("#to_bibxml") { expect(subject.to_bibxml(bib)).to include("<reference") }
    end
  end
end
