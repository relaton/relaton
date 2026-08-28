require "jing"

RSpec.describe Relaton::Bipm::Bibliography do
  context "raise RequestError" do
    it "fetch from GitHub" do
      index = double "index"
      row_id = ::Pubid::Bipm.parse "Metrologia 156"
      expect(index).to receive(:search).and_return [{ id: row_id, file: "data/doc.yaml" }]
      expect(Relaton::Index).to receive(:find_or_create).with(
        :bipm,
        url: "https://raw.githubusercontent.com/relaton/relaton-data-bipm/refs/heads/v2/index-v2.zip",
        file: "index-v2.yaml", pubid_class: ::Pubid::Bipm::Identifier
      ).and_return index
      agent = double(:agent)
      expect(agent).to receive(:get).and_raise Mechanize::ResponseCodeError.new(Mechanize::Page.new)
      expect(Mechanize).to receive(:new).and_return agent
      expect do
        Relaton::Bipm::Bibliography.search "Metrologia"
      end.to raise_error Relaton::RequestError
    end
  end

  context "unparseable reference" do
    it "returns nil (a graceful miss), not a raised error" do
      result = nil
      expect do
        result = Relaton::Bipm::Bibliography.get "not a real bipm ref ((("
      end.not_to raise_error
      expect(result).to be_nil
    end
  end

  context "bib instance" do
    subject do
      Relaton::Bipm::Item.from_yaml File.read("fixtures/bipm_item.yml", encoding: "UTF-8")
    end

    it "returns XML" do
      file = "fixtures/bipm_item.xml"
      xml = subject.to_xml bibdata: true
      File.write file, xml, encoding: "UTF-8" unless File.exist? file
      expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
      schema = Jing.new "../../grammar/relaton-bipm-compile.rng"
      errors = schema.validate file
      expect(errors).to eq []
    end

    it "returns Hash" do
      hash = YAML.safe_load subject.to_yaml
      file = "fixtures/bipm.yaml"
      File.write file, hash.to_yaml, encoding: "UTF-8" unless File.exist? file
      expect(hash).to eq YAML.load_file file
    end

    it "returns AsciiBib" do
      bib = subject.to_asciibib
      file = "fixtures/asciibib.adoc"
      File.write file, bib, encoding: "UTF-8" unless File.exist? file
      expect(bib).to eq File.read(file, encoding: "UTF-8")
    end
  end

  context "get document" do
    before do
      # Force to download index file
      allow_any_instance_of(Relaton::Index::Type).to receive(:actual?).and_return(false)
      allow_any_instance_of(Relaton::Index::FileIO).to receive(:check_file).and_return(nil)
    end

    it "search a code", vcr: "cctf_meeting_14" do
      result = Relaton::Bipm::Bibliography.search "BIPM CCTF Meeting 14 (1999)"
      expect(result).to be_instance_of Relaton::Bipm::ItemData
    end

    context "get document" do
      context "outcomes" do
        it "CCTF Recommendation EN", vcr: "cctf_recommendation_2009_02" do
          file = "fixtures/cctf_recommendation_2009_02.xml"
          result = Relaton::Bipm::Bibliography.get "CCTF Recommendation 2 (2009)"
          xml = result.to_xml(bibdata: true)
          File.write file, xml, encoding: "UTF-8" unless File.exist? file
          expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
            .gsub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s)
        end

        it "CCTF Recommendation EN", vcr: "cctf_recommendation_2009_02" do
          file = "fixtures/cctf_recommendation_2009_02.xml"
          result = Relaton::Bipm::Bibliography.get "CCTF Recommendation 2009-02"
          xml = result.to_xml(bibdata: true)
          File.write file, xml, encoding: "UTF-8" unless File.exist? file
          expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
            .gsub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s)
        end

        it "CCTF Recommendation short notation EN", vcr: "cctf_recommendation_2009_02" do
          file = "fixtures/cctf_recommendation_2009_02.xml"
          result = Relaton::Bipm::Bibliography.get "CCTF REC 2 (2009, EN)"
          xml = result.to_xml(bibdata: true)
          File.write file, xml, encoding: "UTF-8" unless File.exist? file
          expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
            .gsub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s)
        end

        it "CCDS Recommendation", vcr: "cctf_recommendation_2009_02" do
          file = "fixtures/cctf_recommendation_2009_02.xml"
          result = Relaton::Bipm::Bibliography.get "CCDS Recommendation 2 (2009)"
          xml = result.to_xml(bibdata: true)
          File.write file, xml, encoding: "UTF-8" unless File.exist? file
          expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
            .gsub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s)
        end

        it "CGPM meeting", vcr: "cgpm_meeting_1" do
          file = "fixtures/cgpm_meeting_1.xml"
          result = Relaton::Bipm::Bibliography.get "CGPM Meeting 1 (1889)"
          xml = result.to_xml(bibdata: true)
          File.write file, xml, encoding: "UTF-8" unless File.exist? file
          expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
            .gsub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s)
        end

        xit "CGPM resolution", vcr: "cgpm_resolution_1889_00" do
          file = "fixtures/cgpm_resolution_1889_00.xml"
          result = Relaton::Bipm::Bibliography.get "CGPM Resolution (1889)"
          xml = result.to_xml(bibdata: true)
          File.write file, xml, encoding: "UTF-8" unless File.exist? file
          expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
            .gsub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s)
        end

        context "CGPM resolution", vcr: "cgpm_resolution_1889_00" do
          let(:file) { "fixtures/cgpm_resolution_1889_00.xml" }

          xit "CGPM Resolution (1889)" do
            result = Relaton::Bipm::Bibliography.get "CGPM Resolution (1889)"
            xml = result.to_xml(bibdata: true)
            File.write file, xml, encoding: "UTF-8" unless File.exist? file
            expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
              .gsub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s)
          end

          xit "CGPM Resolution 1889-00" do
            result = Relaton::Bipm::Bibliography.get "CGPM Resolution 1889-00"
            expect(result.docidentifier.first.content).to eq "CGPM RES (1889)"
          end

          xit "CGPM RES 1 (1889)" do
            result = Relaton::Bipm::Bibliography.get "CGPM RES 1 (1889)"
            expect(result.docidentifier.first.content).to eq "CGPM RES (1889)"
          end
        end

        # "CGPM DECL (1971)" (the "Pascal and siemens" statement) was intentionally
        # removed from BIPM's upstream source as a cross-referenced duplicate
        # (bipm-data-outcomes dedup commit 6293712, 2026-07-22; the 1901 statements
        # were reclassified as resolutions at the same time). The consumed
        # relaton-data-bipm@v2 correctly reflects that — the record no longer exists —
        # so this identifier resolves to nil. Guard against it silently resolving again.
        it "CGPM Declaration 1971-00 (removed upstream)", vcr: "cgpm_declaration_1971_00" do
          expect(Relaton::Bipm::Bibliography.get("CGPM Declaration 1971-00")).to be_nil
        end

        it "CIPM resolution", vcr: "cipm_resolution_1879" do
          file = "fixtures/cipm_resolution_1879.xml"
          result = Relaton::Bipm::Bibliography.get "CIPM Resolution (1879)"
          xml = result.to_xml(bibdata: true)
          File.write file, xml, encoding: "UTF-8" unless File.exist? file
          expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
            .gsub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s)
        end

        context "CIPM decision", vcr: "cipm_decision_2012_01" do
          it "long notation EN" do
            file = "fixtures/cipm_decision_2012_01.xml"
            result = Relaton::Bipm::Bibliography.get "CIPM Decision 101-1 (2012)"
            xml = result.to_xml(bibdata: true)
            File.write file, xml, encoding: "UTF-8" unless File.exist? file
            expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
              .gsub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s)
          end

          it "short notation EN" do
            file = "fixtures/cipm_decision_2012_01.xml"
            result = Relaton::Bipm::Bibliography.get "CIPM DECN 101-1 (2012, EN)"
            xml = result.to_xml(bibdata: true)
            File.write file, xml, encoding: "UTF-8" unless File.exist? file
            expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
              .sub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s)
          end

          it "short notation language independent" do
            result = Relaton::Bipm::Bibliography.get "CIPM DECN 101-1 (2012)"
            expect(result.docidentifier.first.content).to eq "CIPM DECN 101-1 (2012)"
          end

          it "long notation FR" do
            file = "fixtures/cipm_decision_2012_01.xml"
            result = Relaton::Bipm::Bibliography.get "CIPM Décision 101-1 (2012)"
            xml = result.to_xml(bibdata: true)
            File.write file, xml, encoding: "UTF-8" unless File.exist? file
            expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
              .sub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s)
          end

          it vcr: "cipm_decision_111_10" do
            result = Relaton::Bipm::Bibliography.get "CIPM DECN 111-10 (2022, E)"
            expect(result.docidentifier.first.content).to eq "CIPM DECN 111-10 (2022)"
          end
        end

        context "CIPM Meeting" do
          it "without year", vcr: "cipm_meeting_43_1950" do
            file = "fixtures/cipm_meeting_43_1950.xml"
            result = Relaton::Bipm::Bibliography.get "CIPM Meeting 43"
            xml = result.to_xml(bibdata: true)
            File.write file, xml, encoding: "UTF-8" unless File.exist? file
            expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
              .sub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s)
          end

          it "with year", vcr: "cipm_meeting" do
            result = Relaton::Bipm::Bibliography.get "CIPM 111st Meeting (2022)"
            expect(result.docidentifier.first.content).to eq "CIPM 111st Meeting (2022)"
          end

          it "FR", vcr: "cipm_meeting" do
            result = Relaton::Bipm::Bibliography.get "CIPM 111e Réunion (2022)"
            expect(result.docidentifier.first.content).to eq "CIPM 111st Meeting (2022)"
          end
        end
      end

      it "SI Brochure", vcr: "si_brochure" do
        result = Relaton::Bipm::Bibliography.get "BIPM SI Brochure Part 1"
        en_id = result.docidentifier.find { |id| id.content.is_a?(String) && id.content.end_with?(", E)") }
        expect(en_id.content).to eq "BIPM SI Brochure 9e v3.01 (2019/2024, E)"
      end

      context "Metrologia" do
        it "journal" do
          VCR.use_cassette "metrologia" do
            file = "fixtures/metrologia.xml"
            result = Relaton::Bipm::Bibliography.get "BIPM Metrologia"
            xml = result.to_xml bibdata: true
            File.write file, xml, encoding: "UTF-8" unless File.exist? file
            expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
              .sub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s)
          end
        end

        it "journal" do
          VCR.use_cassette "metrologia_30" do
            file = "fixtures/metrologia_30.xml"
            result = Relaton::Bipm::Bibliography.get "BIPM Metrologia 30"
            xml = result.to_xml bibdata: true
            File.write file, xml, encoding: "UTF-8" unless File.exist? file
            expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
              .sub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s)
          end
        end

        it "volume" do
          VCR.use_cassette "metrologia_29_6" do
            file = "fixtures/metrologia_29_6.xml"
            result = Relaton::Bipm::Bibliography.get "BIPM Metrologia 29 6"
            xml = result.to_xml bibdata: true
            File.write file, xml, encoding: "UTF-8" unless File.exist? file
            expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
              .sub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s)
          end
        end

        it "volume with title" do
          VCR.use_cassette "metrologia_30_4" do
            file = "fixtures/metrologia_30_4.xml"
            result = Relaton::Bipm::Bibliography.get "BIPM Metrologia 30 4"
            xml = result.to_xml bibdata: true
            File.write file, xml, encoding: "UTF-8" unless File.exist? file
            expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
              .sub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s)
          end
        end

        it "page" do
          VCR.use_cassette "metrologia_29_6_373" do
            file = "fixtures/metrologia_29_6_373.xml"
            result = Relaton::Bipm::Bibliography.get "BIPM Metrologia 29 6 373"
            xml = result.to_xml bibdata: true
            File.write file, xml, encoding: "UTF-8" unless File.exist? file
            expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
              .sub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s)
          end
        end

        it "wrong page" do
          expect do
            result = Relaton::Bipm::Bibliography.get "BIPM Metrologia 34 3 999"
            expect(result).to be_nil
          end.to output(
            /\[relaton-bipm\] INFO: \(BIPM Metrologia 34 3 999\) Not found\./,
          ).to_stderr_from_any_process
        end

        it "with 403 response code", vcr: "metrologia_50_4_385" do
          result = Relaton::Bipm::Bibliography.get "BIPM Metrologia 50 4 385"
          expect(result.docidentifier[0].content).to eq "Metrologia 50 4 385"
        end

        it "without author", vcr: "metrologia_19_4_163" do
          result = Relaton::Bipm::Bibliography.get "BIPM Metrologia 19 4 163"
          expect(result.docidentifier[0].content).to eq "Metrologia 19 4 163"
        end

        it "with text/html title", vcr: "metrologia_55_1_L13" do
          result = Relaton::Bipm::Bibliography.get "BIPM Metrologia 55 1 L13"
          expect(result.title[0].content).to eq(
            "The CODATA 2017 values of <em>h</em>, <em>e</em>, <em>k</em>, " \
            "and <em>N</em><sub>A</sub> for the revision of the SI",
          )
        end
      end
    end

    # JCGM retrieval moved to the dedicated `Relaton::Jcgm` flavor
    # (spec/jcgm/); the BIPM flavor no longer serves JCGM documents.
  end

  # The index lookup narrows candidate rows by number before it applies the
  # fuzzy `Id#==` block. `Relaton::Index::Type#search` binary-searches only when
  # it is given an identifier, so a pubid is parsed purely to supply that key.
  # The BIPM lookup matches pubid to pubid, like every other pubid-backed
  # flavor. `Relaton::Bipm::Id` is retained for the `relaton-data-bipm` crawler
  # but no longer takes part in a query.
  context "pubid lookup" do
    # Run a lookup without fetching the document, reporting how many rows the
    # match saw and how many times `#search` was called. The call count is what
    # separates a narrowed lookup from one that missed and rescanned; an empty
    # bucket contributes no scanned rows of its own.
    def lookup(reference)
      index = described_class.index
      original = index.method(:search)
      scanned = 0
      calls = 0
      allow(described_class).to receive(:index).and_return index
      allow(index).to receive(:search) do |*args, &block|
        calls += 1
        original.call(*args) do |row|
          scanned += 1
          block.call row
        end
      end
      rows = described_class.search_index described_class.parse_ref(reference), reference
      [rows, scanned, calls]
    end

    let(:index_size) { described_class.index.index.size }

    # The load-bearing guard for retiring `Id`. Every reference the suite
    # exercises must resolve to exactly the files it resolved to under the
    # bespoke grammar. The expectations are pinned literally, captured from the
    # `Id` implementation before it was removed, so they cannot drift with the
    # code they check.
    context "resolves every reference to the same record as the Id grammar did" do
      baseline = {
        "CCDS Recommendation 2 (2009)" => ["data/cctf/meeting/recommendation/2009-02.yaml"],
        "CCTF Meeting 14 (1999)" => ["data/cctf/meeting/14.yaml"],
        "CCTF REC 2 (2009, EN)" => ["data/cctf/meeting/recommendation/2009-02.yaml"],
        "CCTF Recommendation 2 (2009)" => ["data/cctf/meeting/recommendation/2009-02.yaml"],
        "CCTF Recommendation 2009-02" => ["data/cctf/meeting/recommendation/2009-02.yaml"],
        "CGPM Meeting 1 (1889)" => ["data/cgpm/meeting/1.yaml"],
        "CGPM RES 1 (1889)" => [],
        "CGPM Resolution (1889)" => [],
        "CGPM Resolution 1889-00" => [],
        "CIPM 111e Réunion (2022)" => ["data/cipm/meeting/111.yaml"],
        "CIPM 111st Meeting (2022)" => ["data/cipm/meeting/111.yaml"],
        "CIPM DECN 101-1 (2012)" => ["data/cipm/meeting/decision/2012-101-1.yaml"],
        "CIPM DECN 101-1 (2012, EN)" => ["data/cipm/meeting/decision/2012-101-1.yaml"],
        "CIPM DECN 111-10 (2022, E)" => ["data/cipm/meeting/decision/2022-111-10.yaml"],
        "CIPM Decision 101-1 (2012)" => ["data/cipm/meeting/decision/2012-101-1.yaml"],
        "CIPM Décision 101-1 (2012)" => ["data/cipm/meeting/decision/2012-101-1.yaml"],
        "CIPM Meeting 43" => ["data/cipm/meeting/43.yaml"],
        "CIPM Resolution (1879)" => ["data/cipm/meeting/resolution/1879-00.yaml"],
        # Number-less declarations are reachable both ways: `Id#==`
        # collapsed number "1" with none when both carried a year.
        "CIPM Resolution 1 (1879)" => ["data/cipm/meeting/resolution/1879-00.yaml"],
        "CGPM Declaration 1 (1889)" => ["data/cgpm/meeting/statement/1889-00.yaml"],
        "Metrologia" => ["data/metrologia.yaml"],
        "Metrologia 19 4 163" => ["data/metrologia-19-4-163.yaml"],
        "Metrologia 29 6" => ["data/metrologia-29-6.yaml"],
        "Metrologia 29 6 373" => ["data/metrologia-29-6-373.yaml"],
        "Metrologia 30" => ["data/metrologia-30.yaml"],
        "Metrologia 30 4" => ["data/metrologia-30-4.yaml"],
        "Metrologia 34 3 999" => [],
        "Metrologia 50 4 385" => ["data/metrologia-50-4-385.yaml"],
        "Metrologia 55 1 L13" => ["data/metrologia-55-1-l13.yaml"],
        "SI Brochure Part 1" => ["data/si-brochure.yaml", "data/si-brochure.yaml"],
        "not a real bipm ref (((" => [],      }.freeze

      baseline.each do |reference, expected|
        it reference.inspect do
          pubid = described_class.parse_ref reference
          rows = pubid ? described_class.search_index(pubid, reference) : []
          expect(rows.map { |r| r[:file] }.sort).to eq expected
        end
      end
    end

    context "#parse_ref" do
      it "parses a loose consumer form with the pubid grammar" do
        expect(described_class.parse_ref("CCDS Recommendation 2 (2009)").to_s)
          .to eq "CCTF Recommendation 2 (2009)"
      end

      it "returns nil for an unparseable reference rather than raising" do
        expect { described_class.parse_ref "((( nonsense" }.not_to raise_error
        expect(described_class.parse_ref("((( nonsense")).to be_nil
      end
    end

    context "#pubid_match?" do
      # Rows are stored language- and form-neutral; a reference may name a
      # language and always names a form.
      it "ignores the language and the form" do
        row = ::Pubid::Bipm.parse "CCTF Recommendation 2 (2009)"
        ["CCTF REC 2 (2009, EN)", "CCTF Recommendation 2 (2009)"].each do |ref|
          expect(described_class.pubid_match?(row, ::Pubid::Bipm.parse(ref))).to be true
        end
      end

      # `CIPM Meeting 43` carries no year but its row does. Excluding only
      # language and form leaves them unequal, which is the correction this
      # flavor makes to the hand-off's recipe.
      it "ignores the year when the query carries none" do
        row = ::Pubid::Bipm.parse "CIPM 43rd Meeting (1950)"
        expect(described_class.pubid_match?(row, ::Pubid::Bipm.parse("CIPM Meeting 43"))).to be true
      end

      it "keeps the year when the query supplies one" do
        row = ::Pubid::Bipm.parse "CIPM 43rd Meeting (1950)"
        query = ::Pubid::Bipm.parse "CIPM 43rd Meeting (1999)"
        expect(described_class.pubid_match?(row, query)).to be false
      end

      # A bare brochure names no edition, so it is a partial reference. This is
      # what `Id#id_hash`'s {group, type} collapse meant.
      it "matches any brochure row for an edition-less brochure query" do
        row = ::Pubid::Bipm.parse "BIPM SI Brochure 9e v3.01 (2019/2024, E)"
        expect(described_class.pubid_match?(row, ::Pubid::Bipm.parse("SI Brochure"))).to be true
      end
    end

    # `#pubid_match?` rejects on CHEAP_KEYS before building the stem, because
    # `#exclude` copies the identifier and doing that per row cost ~165x a
    # plain attribute read. The optimisation is only sound if stem equality
    # implies equality on every one of those keys. Settle it by assertion
    # rather than by argument, over the real corpus.
    it "never rejects a row whose stem matches the query" do
      rows = described_class.index.index
      sample = rows.each_slice(40).map(&:first)
      wrong = sample.reject do |row|
        query = row[:id]
        # The stem is what decides; the cheap keys must not veto it.
        described_class.stem(row[:id], query) != described_class.stem(query, query) ||
          described_class.send(:cheap_reject_passes?, row[:id], query)
      end
      expect(sample.size).to be > 150
      expect(wrong.map { |r| r[:file] }).to eq []
    end

    context "#search_index" do
      it "scans only the number bucket when the query keys to its row" do
        rows, scanned, calls = lookup "CCTF Recommendation 2 (2009)"
        expect(rows.map { |r| r[:file] }).to eq ["data/cctf/meeting/recommendation/2009-02.yaml"]
        expect(calls).to eq 1
        expect(scanned).to be < index_size / 10
      end

      # A bare brochure keys to "" while its row keys to its edition "9e", so
      # the narrowed range cannot contain it and only the rescan finds it. The
      # "" bucket is not empty — it holds the six ordinal-less declarations and
      # the journal-level Metrologia record — so the narrowed pass scans those
      # seven first, and the total exceeds a single scan.
      it "rescans the whole index when the narrowed range does not match" do
        rows, scanned, calls = lookup "SI Brochure Part 1"
        expect(rows.map { |r| r[:file] }.uniq).to eq ["data/si-brochure.yaml"]
        expect(calls).to eq 2
        expect(scanned).to be > index_size
      end

      # `2009-02` parses as the literal number, while the row keys on 2. A
      # rescan cannot recover it -- no row carries that number -- so the
      # reference is retried as number plus year.
      it "retries a trailing YYYY-NN as number and year" do
        rows, = lookup "CCTF Recommendation 2009-02"
        expect(rows.map { |r| r[:file] }).to eq ["data/cctf/meeting/recommendation/2009-02.yaml"]
      end

      it "returns no rows for a reference that is not in the index" do
        rows, = lookup "Metrologia 34 3 999"
        expect(rows).to be_empty
      end
    end

    context "#year_number_retry" do
      it "rewrites a trailing YYYY-NN and strips the leading zero" do
        expect(described_class.year_number_retry("CCTF Recommendation 2009-02").to_s)
          .to eq "CCTF Recommendation 2 (2009)"
      end

      it "returns nil when the reference has no trailing YYYY-NN" do
        expect(described_class.year_number_retry("CCTF Recommendation 2 (2009)")).to be_nil
      end

      it "returns nil for a nil reference" do
        expect(described_class.year_number_retry(nil)).to be_nil
      end
    end
  end
end
