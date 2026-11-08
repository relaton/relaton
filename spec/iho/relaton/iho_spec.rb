RSpec.describe Relaton::Iho do
  # Builds a real `Relaton::Index::Type` from rows, so `search` exercises
  # the flavor's matcher and recency key over real pubid rows (relaton#407
  # replaced the double that answered `search` with canned rows here).
  def stub_index(rows)
    file = File.join(Dir.mktmpdir("relaton-iho-idx"), "#{Relaton::Iho::INDEXFILE}.yaml")
    # The loader warns on an unsorted index; rows share the narrowing key
    # order the consumer sorts by.
    File.write file, YAML.dump(rows.sort_by { |r| r[:id]["number"].to_s })
    type = Relaton::Index::Type.new(:iho, file: file, pubid_class: ::Pubid::Iho::Identifier)
    type.index
    allow(Relaton::Iho::Bibliography).to receive(:index).and_return(type)
  end

  # One index row: the pubid hash a data repo commits, and the file it
  # names.
  def row(ref, file)
    { id: Pubid::Iho::Identifier.parse(ref).to_hash, file: file }
  end

  it "has a version number" do
    expect(Relaton::VERSION).not_to be nil
  end

  it "retur grammar hash" do
    hash = Relaton::Iho.grammar_hash
    expect(hash).to be_instance_of String
    expect(hash.size).to eq 32
  end

  it "search a code", vcr: "b_11" do
    result = Relaton::Iho::Bibliography.search "IHO B-11"
    expect(result).to be_instance_of Relaton::Iho::ItemData
  end

  context "get document" do
    it "by code", vcr: "b_11" do
      expect do
        file = "fixtures/b_11.xml"
        result = Relaton::Iho::Bibliography.get "IHO B-11"
        xml = result.to_xml bibdata: true
        File.write file, xml, encoding: "UTF-8" unless File.exist? file
        expect(xml).to be_xml_equivalent_to File.read(file, encoding: "UTF-8")
          .sub(/(?<=<fetched>).*(?=<\/fetched>)/, Date.today.to_s)
        schema = Relaxng.new "../../grammar/relaton-iho-compile.rng"
        errors = schema.validate file
        expect(errors).to eq []
      end.to output(
        /\[relaton-iho\] INFO: \(IHO B-11\) Fetching from Relaton repository \.\.\./
      ).to_stderr_from_any_process
    end

    it "by code", vcr: "iho_s63" do
      result = Relaton::Iho::Bibliography.get "IHO S-63"
      expect(result.docidentifier.first.content).to eq "S-63"
    end

    it "raises on unparseable reference" do
      expect { Relaton::Iho::Bibliography.get "IHO S63" }
        .to raise_error(StandardError)
    end

    it "by code and edition", vcr: { cassette_name: "code_and_edition" } do
      result = Relaton::Iho::Bibliography.get "IHO B-6 4.2.0"
      expect(result.docidentifier.first.content).to eq "B-6"
      expect(result.edition.content).to eq "4.2.0"
    end

    # An unqualified reference answers with the latest edition. Only the
    # selected file is stubbed, so a wrong pick hits WebMock's net block.
    context "without an edition" do
      def stub_doc(file, edition)
        stub_request(:get, "#{Relaton::Iho::Bibliography::ENDPOINT}data/#{file}")
          .to_return(body: "---\ndocidentifier:\n- content: B-12\n  type: IHO\n  " \
                           "primary: true\nedition:\n  content: #{edition}\n")
      end

      def stub_rows(refs_to_files)
        stub_index refs_to_files.map { |ref, file| row(ref, file) }
      end

      it "takes the latest edition" do
        stub_doc "b-12_3-0-0.yaml", "3.0.0"
        result = Relaton::Iho::Bibliography.get "IHO B-12"
        expect(result.edition.content).to eq "3.0.0"
      end

      # The string min (1.0.0) and the string max (2.9.0) are both wrong.
      it "orders edition segments as numbers" do
        stub_rows(
          "IHO B-12 1.0.0" => "data/b-12_1-0-0.yaml",
          "IHO B-12 2.9.0" => "data/b-12_2-9-0.yaml",
          "IHO B-12 2.10.0" => "data/b-12_2-10-0.yaml",
        )
        stub_doc "b-12_2-10-0.yaml", "2.10.0"
        result = Relaton::Iho::Bibliography.get "IHO B-12"
        expect(result.edition.content).to eq "2.10.0"
      end
    end

    # relaton#440: the series publications are identified by a volume
    # locator (the yearbook year IS a volume) or, for edition-keyed
    # products like P-7, by their dotted edition. The bare-year faces of
    # the #48 re-key parse as legacy aliases into the volume slot. The
    # fixture index carries the round-2 rows (relaton-data-iho#52); the
    # selected file is stubbed, so a wrong pick hits WebMock's net block.
    context "series identified by volume or edition" do
      def stub_doc(file, docid)
        stub_request(:get, "#{Relaton::Iho::Bibliography::ENDPOINT}#{file}")
          .to_return(body: "---\ndocidentifier:\n- content: #{docid}\n  type: IHO\n  primary: true\n")
      end

      it "resolves a volume-identified series document" do
        stub_doc "data/p-5_vol-2020.yaml", "P-5 Vol. 2020"
        result = Relaton::Iho::Bibliography.get "IHO P-5 Vol. 2020"
        expect(result.docidentifier.first.content).to eq "P-5 Vol. 2020"
      end

      # The bare-year face is a parse-only legacy alias: it binds into
      # the volume and answers the volume's record (relaton#440 gate).
      it "resolves a bare-year alias to its volume record" do
        stub_doc "data/p-5_vol-2020.yaml", "P-5 Vol. 2020"
        result = Relaton::Iho::Bibliography.get "IHO P-5 2020"
        expect(result.docidentifier.first.content).to eq "P-5 Vol. 2020"
      end

      it "resolves a volume-identified B-series document" do
        stub_doc "data/b-7_vol-2003.yaml", "B-7 Vol. 2003"
        result = Relaton::Iho::Bibliography.get "IHO B-7 Vol. 2003"
        expect(result.docidentifier.first.content).to eq "B-7 Vol. 2003"
      end

      it "resolves a conference series document by its volume" do
        stub_doc "data/p-6_vol-2023.yaml", "P-6 Vol. 2023"
        result = Relaton::Iho::Bibliography.get "IHO P-6 Vol. 2023"
        expect(result.docidentifier.first.content).to eq "P-6 Vol. 2023"
      end

      it "resolves a volume- and issue-identified series document" do
        stub_doc "data/p-1_vol-30-1.yaml", "P-1 Vol. 30 (1)"
        result = Relaton::Iho::Bibliography.get "IHO P-1 Vol. 30 (1)"
        expect(result.docidentifier.first.content).to eq "P-1 Vol. 30 (1)"
      end

      # The issue the query omits is a wildcard: any issue of the named
      # volume answers — including through the compact slash-chain face
      # (relaton#440: `IHO P-1/30` resolves again).
      it "answers a volume-only query" do
        stub_doc "data/p-1_vol-30-1.yaml", "P-1 Vol. 30 (1)"
        result = Relaton::Iho::Bibliography.get "IHO P-1 Vol. 30"
        expect(result.docidentifier.first.content).to eq "P-1 Vol. 30 (1)"
      end

      it "answers the compact slash-chain volume face" do
        stub_doc "data/p-1_vol-30-1.yaml", "P-1 Vol. 30 (1)"
        result = Relaton::Iho::Bibliography.get "IHO P-1/30"
        expect(result.docidentifier.first.content).to eq "P-1 Vol. 30 (1)"
      end

      # A query that names no component takes the latest of the series:
      # the latest volume for a volume series (relaton#440 folded the
      # year locators in), the newest edition for an edition-keyed
      # product — not a year.
      it "answers a bare series query with the latest volume" do
        stub_doc "data/p-5_vol-2020.yaml", "P-5 Vol. 2020"
        result = Relaton::Iho::Bibliography.get "IHO P-5"
        expect(result.docidentifier.first.content).to eq "P-5 Vol. 2020"
      end

      it "answers a bare edition-keyed series query with the newest edition" do
        stub_doc "data/p-7_1-0-9.yaml", "P-7"
        result = Relaton::Iho::Bibliography.get "IHO P-7"
        expect(result.docidentifier.first.content).to eq "P-7"
      end

      it "answers a bare series query with the latest volume and issue" do
        stub_doc "data/p-1_vol-30-1.yaml", "P-1 Vol. 30 (1)"
        result = Relaton::Iho::Bibliography.get "IHO P-1"
        expect(result.docidentifier.first.content).to eq "P-1 Vol. 30 (1)"
      end

      # The placeholder edition is gone from the series: a `1.0.0`
      # reference names no real document (relaton-data-iho#20).
      it "does not answer a placeholder-edition query" do
        expect(Relaton::Iho::Bibliography.get "IHO P-5 1.0.0").to be_nil
      end
    end

    # The ordering rules, over a purpose-built index — the fixture pins
    # the row shapes, these pin the recency key's comparisons.
    context "series recency selection" do
      def stub_doc(file, docid)
        stub_request(:get, "#{Relaton::Iho::Bibliography::ENDPOINT}#{file}")
          .to_return(body: "---\ndocidentifier:\n- content: #{docid}\n  type: IHO\n  primary: true\n")
      end

      it "orders volumes as numbers" do
        stub_index [
          row("IHO P-1 Vol. 9", "data/p-1_vol-9.yaml"),
          row("IHO P-1 Vol. 30", "data/p-1_vol-30.yaml"),
        ]
        stub_doc "data/p-1_vol-30.yaml", "P-1 Vol. 30"
        result = Relaton::Iho::Bibliography.get "IHO P-1"
        expect(result.docidentifier.first.content).to eq "P-1 Vol. 30"
      end

      it "orders issues as numbers" do
        stub_index [
          row("IHO P-1 Vol. 30 (9)", "data/p-1_vol-30-9.yaml"),
          row("IHO P-1 Vol. 30 (10)", "data/p-1_vol-30-10.yaml"),
        ]
        stub_doc "data/p-1_vol-30-10.yaml", "P-1 Vol. 30 (10)"
        result = Relaton::Iho::Bibliography.get "IHO P-1 Vol. 30"
        expect(result.docidentifier.first.content).to eq "P-1 Vol. 30 (10)"
      end

      # A stated component pins the record; the latest row of the series
      # must not answer over it.
      it "answers a stated year with that year, not the latest" do
        stub_index [
          row("IHO P-5 2023", "data/p-5_2023.yaml"),
          row("IHO P-5 2024", "data/p-5_2024.yaml"),
        ]
        stub_doc "data/p-5_2023.yaml", "P-5 2023"
        result = Relaton::Iho::Bibliography.get "IHO P-5 2023"
        expect(result.docidentifier.first.content).to eq "P-5 2023"
      end

      it "answers a stated issue with that issue, not the latest" do
        stub_index [
          row("IHO P-1 Vol. 30 (9)", "data/p-1_vol-30-9.yaml"),
          row("IHO P-1 Vol. 30 (10)", "data/p-1_vol-30-10.yaml"),
        ]
        stub_doc "data/p-1_vol-30-9.yaml", "P-1 Vol. 30 (9)"
        result = Relaton::Iho::Bibliography.get "IHO P-1 Vol. 30 (9)"
        expect(result.docidentifier.first.content).to eq "P-1 Vol. 30 (9)"
      end
    end

    it "take doc with shorter code", vcr: "s_4" do
      result = Relaton::Iho::Bibliography.get "IHO S-4"
      expect(result.docidentifier.first.content).to eq "S-4"
    end

    it "not found", vcr: { cassette_name: "not_found" } do
      expect do
        expect(Relaton::Iho::Bibliography.get("IHO B-1111")).to be_nil
      end.to output(/\[relaton-iho\] INFO: \(IHO B-1111\) Not found\./).to_stderr_from_any_process
    end

    # Routing tests for the new structured-identifier attributes
    # introduced for relaton/relaton-iho#23 / metanorma-iho#344. Each
    # exercises a different pubid field (part / annex / appendix /
    # supplement) plus the umbrella-vs-subdivision disambiguation.
    it "by part", vcr: "iho_s100_part5" do
      result = Relaton::Iho::Bibliography.get "IHO S-100 Part 5 5.2.0"
      expect(result.docidentifier.first.content).to eq "S-100 Part 5"
    end

    it "by annex", vcr: "iho_s100_annex_a" do
      result = Relaton::Iho::Bibliography.get "IHO S-100 Annex A 5.2.0"
      expect(result.docidentifier.first.content).to eq "S-100 Annex A"
    end

    # Exercises both the `Appendix` wording and the `D-2` letter-digit
    # value form added to pubid-iho.
    it "by appendix with letter-digit value", vcr: "iho_s122_appendix_d_2" do
      result = Relaton::Iho::Bibliography.get "IHO S-122 Appendix D-2 1.0.0"
      expect(result.docidentifier.first.content).to eq "S-122 Appendix D-2"
    end

    it "by supplement", vcr: "iho_s66_suppl1" do
      result = Relaton::Iho::Bibliography.get "IHO S-66 Suppl 1 2.0.0"
      expect(result.docidentifier.first.content).to eq "S-66 Suppl 1"
    end

    # An unqualified umbrella query must not get hijacked by a
    # subdivision row even though the index now contains many
    # `:part: …` rows under :number 100.
    it "umbrella query bypasses subdivision rows", vcr: "iho_s100_umbrella" do
      result = Relaton::Iho::Bibliography.get "IHO S-100 5.2.0"
      expect(result.docidentifier.first.content).to eq "S-100"
    end
  end

  context "bib instance" do
    let(:yaml) { File.read "fixtures/item.yaml", encoding: "UTF-8" }

    it "create item from yaml" do
      item = Relaton::Iho::Item.from_yaml yaml
      xml = item.to_xml bibdata: true
      file = "fixtures/iho.xml"
      File.write file, xml, encoding: "UTF-8" unless File.exist? file
      expect(xml).to be_xml_equivalent_to File.read(file, encoding: "UTF-8")
    end
  end

  it "check XML grammar" do
    schema = Relaxng.new "../../grammar/relaton-iho-compile.rng"
    errors = schema.validate "fixtures/bibdata.xml"
    expect(errors).to eq []
  end
end
