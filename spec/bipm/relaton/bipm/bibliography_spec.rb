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
  context "index narrowing" do
    # Run a lookup without fetching the document, reporting both how many rows
    # the fuzzy block saw and how many times `#search` was called. The call
    # count is what distinguishes a narrowed lookup (one call) from one that
    # narrowed, missed, and fell back (two calls) — the scanned count cannot,
    # because an empty bucket contributes no rows at all.
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
      rows = described_class.search_index reference, described_class.parse_ref(reference)
      [rows, scanned, calls]
    end

    # The unconditional full scan this lookup did before the narrowing.
    def full_scan(reference)
      ref_id = described_class.parse_ref reference
      described_class.index.search { |r| ref_id == described_class.id_hash(r[:id]) }
    end

    let(:index_size) { described_class.index.index.size }

    context "#narrowing_id" do
      it "returns the pubid for a reference the pubid grammar accepts" do
        pubid = described_class.narrowing_id "CCTF Recommendation 2 (2009)"
        expect(pubid).to be_a ::Pubid::Bipm::Identifiers::CommitteeDocument
        expect(pubid.root.number.to_s).to eq "2"
      end

      # pubid used to reject the loose consumer forms, which is why narrowing
      # is best-effort. It now accepts every form `Id` accepts, so those
      # references narrow instead of scanning. Kept as a guard: if the pubid
      # grammar ever narrows again, this fails and says which form regressed.
      it "derives a key for every loose form the suite exercises" do
        loose = ["CCTF Meeting 14 (1999)", "CGPM Meeting 1 (1889)",
                 "CIPM Meeting 43", "CIPM 111e Réunion (2022)",
                 "CIPM Décision 101-1 (2012)", "CCDS Recommendation 2 (2009)",
                 "CCTF REC 2 (2009, EN)", "SI Brochure Part 1"]
        expect(loose.reject { |ref| described_class.narrowing_id ref }).to eq []
      end

      it "returns nil for an unparseable reference rather than raising" do
        expect { described_class.narrowing_id "((( nonsense" }.not_to raise_error
        expect(described_class.narrowing_id("((( nonsense")).to be_nil
      end
    end

    context "#search_index" do
      it "scans only the number bucket when pubid and the index agree" do
        rows, scanned, calls = lookup "CCTF Recommendation 2 (2009)"
        expect(rows.size).to eq 1
        expect(rows.first[:file]).to eq "data/cctf/meeting/recommendation/2009-02.yaml"
        expect(calls).to eq 1
        expect(scanned).to be < index_size / 10
      end

      # `Id` reads `2009-02` as year 2009 / number 2; pubid reads it as the
      # literal number `2009-02`. The narrowed bucket is empty, so only the
      # full scan recovers the row.
      it "falls back to the full scan when the narrowed bucket misses" do
        rows, scanned, calls = lookup "CCTF Recommendation 2009-02"
        expect(rows.size).to eq 1
        expect(rows.first[:file]).to eq "data/cctf/meeting/recommendation/2009-02.yaml"
        # Two calls: the narrowed one that found nothing, then the full scan.
        # The bucket is empty, so it contributes no scanned rows of its own.
        expect(calls).to eq 2
        expect(scanned).to eq index_size
      end

      # The no-narrowing branch. pubid now parses every reference `Id` parses,
      # so no real reference reaches it; drive it by withholding the key
      # instead, because the branch still has to work if that changes.
      it "scans everything when no narrowing key can be derived" do
        allow(described_class).to receive(:narrowing_id).and_return nil
        rows, scanned, calls = lookup "CCDS Recommendation 2 (2009)"
        expect(rows.size).to eq 1
        expect(calls).to eq 1
        expect(scanned).to eq index_size
      end

      it "still resolves a number-less committee document" do
        rows, = lookup "CIPM Resolution (1879)"
        expect(rows.size).to eq 1
        expect(rows.first[:file]).to eq "data/cipm/meeting/resolution/1879-00.yaml"
      end

      it "still resolves a Metrologia article" do
        rows, = lookup "Metrologia 29 6 373"
        expect(rows.size).to eq 1
      end

      it "returns no rows for a reference that is not in the index" do
        rows, = lookup "Metrologia 34 3 999"
        expect(rows).to be_empty
      end
    end

    # The fallback fires only on an EMPTY narrowed range. A query whose matches
    # straddle two buckets would therefore lose one silently, without ever
    # falling back. `Id#==` collapses number "1" and no number when a year is
    # present, and that is the same field the index buckets on, so the two
    # can in principle disagree.
    #
    # These two examples settle it by assertion rather than by argument: the
    # rows `#search_index` returns must equal the rows the unconditional full
    # scan returns, for every reference checked.
    context "equivalence with the full scan" do
      # Every reference that can straddle the "1"/"" boundary: the rows with no
      # number, and every row numbered "1".
      it "agrees on every reference that could straddle two buckets" do
        rows = described_class.index.index.select do |row|
          number = described_class.id_hash(row[:id])[:number]
          number.nil? || number.to_s == "1"
        end
        expect(rows.size).to be > 50
        expect(mismatches(rows)).to eq []
      end

      it "agrees on a sample drawn from across the index" do
        rows = described_class.index.index.each_slice(60).map(&:first)
        expect(rows.size).to be > 100
        expect(mismatches(rows)).to eq []
      end

      # Query the index by each row's own rendered identifier and report the
      # rows where narrowing changed the result.
      def mismatches(rows)
        rows.filter_map do |row|
          reference = row[:id].to_s
          narrowed = described_class.search_index reference, described_class.parse_ref(reference)
          full = full_scan reference
          next if narrowed.map { |r| r[:file] }.sort == full.map { |r| r[:file] }.sort

          reference
        rescue Relaton::RequestError
          nil # `Id` cannot parse this row's rendering; no lookup is possible
        end
      end
    end

    # Guards the derivation against drift: the key pubid derives from a query
    # must equal the key the index sorted the row under. Only the two families
    # whose rows carry a number can be checked today; Metrologia and SI
    # Brochure rows key to "" until pubid derives a number for them.
    it "derives the same key from a query as the index stored for the row" do
      families = [::Pubid::Bipm::Identifiers::CommitteeDocument,
                  ::Pubid::Bipm::Identifiers::Meeting]
      rows = described_class.index.index.select do |row|
        families.any? { |f| row[:id].is_a? f } && !row[:id].number.to_s.empty?
      end
      expect(rows.size).to be > 1_500
      mismatched = rows.reject do |row|
        pubid = described_class.narrowing_id row[:id].to_s
        pubid && pubid.root.number.to_s == row[:id].root.number.to_s
      end
      expect(mismatched.map { |r| r[:file] }).to eq []
    end
  end
end
