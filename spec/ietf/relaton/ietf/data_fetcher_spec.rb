require "tmpdir"
require "relaton/ietf/data_fetcher"

RSpec.describe Relaton::Ietf::DataFetcher do
  # `write_unique` creates with O_EXCL so a peer process cannot be clobbered.
  EXCL = Relaton::Core::DataFetcher::EXCLUSIVE

  let(:index) do
    idx = double("index")
    allow(idx).to receive(:add_or_update)
    allow(idx).to receive(:save)
    idx
  end

  before(:each) do
    allow(Relaton::Index).to receive(:find_or_create)
      .with(:IETF, url: nil, file: "index-v2.yaml",
            pubid_class: ::Pubid::Ietf::Identifier).and_return(index)
  end

  # The index stores parsed pubids, not strings: `FileIO#save` only serialises
  # an id to its `_type:` hash when it is an instance of the configured
  # `pubid_class`, so a String here would write a v1-shaped file under a v2
  # name. Matching on the rendered form keeps these expectations readable.
  def pubid(str)
    ::Pubid::Ietf::Identifier.parse str
  end

  # it "fetch rfc index" do
  #   VCR.use_cassette "ietf_rfc_index" do
  #     described_class.fetch "ietf-rfcsubseries", format: "bibxml"
  #   end
  # end

  # it "fetch internet-drafts" do
  #   VCR.use_cassette "ietf_internet_drafts" do
  #     described_class.fetch "ietf-internet-drafts"
  #   end
  # end

  # it "fetch ietf-rfc-entries" do
  #   VCR.use_cassette "ietf_rfc_entries" do
  #     described_class.fetch "ietf-rfc-entries"
  #   end
  # end

  it "create output dir and run fetcher" do
    expect(FileUtils).to receive(:mkdir_p).with("dir")
    fetcher = double("fetcher")
    expect(fetcher).to receive(:fetch).with("source")
    expect(described_class).to receive(:new).with("dir", "xml").and_return(fetcher)
    described_class.fetch "source", output: "dir", format: "xml"
  end

  context "instance ietf-rfcsubseries" do
    subject { described_class.new("dir", "yaml") }

    before do
      xml = File.read "fixtures/ietf_rfcsubseries.xml"
      allow(Net::HTTP).to receive(:get).and_return(xml)
      allow(Relaton::Ietf::WgNameResolver).to receive(:fetch).and_return({})
    end

    it "fetch data" do
      expect(subject).to receive(:save_doc).exactly(11).times
      expect(index).to receive(:save)
      subject.fetch "ietf-rfcsubseries"
    end
  end

  context "instance ietf-internet-drafts" do
    subject { described_class.new("dir", "yaml") }

    # Force serial Parallel.map so mocks work and results are deterministic.
    before do
      allow(Parallel).to receive(:map) { |items, **_, &block| items.map(&block) }
    end

    it "initialize fetcher" do
      expect(subject.instance_variable_get(:@ext)).to eq "yaml"
      expect(subject.instance_variable_get(:@files)).to be_a Set
      expect(subject.instance_variable_get(:@output)).to eq "dir"
      expect(subject.instance_variable_get(:@format)).to eq "yaml"
      expect(subject).to be_instance_of(described_class)
    end

    it "fetch data: groups paths, parallelizes work, records index entries" do
      series_groups = { "draft-x" => [{ path: "p", ver: "00", ref: "draft-x-00" }] }
      singleton_paths = ["bibxml-ids/extra.xml"]
      expect(subject).to receive(:group_draft_paths).and_return([series_groups, singleton_paths])

      series_result = [{ docnumber: "draft-x-00", file: "dir/draft-x-00.yaml", index_id: "draft-x-00" }]
      singleton_result = { docnumber: "extra", file: "dir/extra.yaml", index_id: "extra" }
      expect(subject).to receive(:process_series).with("draft-x", series_groups["draft-x"]).and_return(series_result)
      expect(subject).to receive(:process_singleton).with("bibxml-ids/extra.xml").and_return(singleton_result)
      expect(subject).to receive(:record_index_entry).with(series_result.first)
      expect(subject).to receive(:record_index_entry).with(singleton_result)
      expect(index).to receive(:save)

      subject.fetch "ietf-internet-drafts"
    end

    describe "#group_draft_paths" do
      it "groups versioned drafts under normalized series stem (no XML parsed)" do
        paths = [
          "bibxml-ids/reference.I-D.draft-collins-pfr-00.xml",
          "bibxml-ids/reference.I-D.draft-collins-pfr-01.xml",
        ]
        expect(Dir).to receive(:[]).with("bibxml-ids/*.xml").and_return(paths)
        expect(File).not_to receive(:read)
        expect(Relaton::Ietf::BibXMLParser).not_to receive(:parse)

        series_groups, singletons = subject.send(:group_draft_paths)
        expect(singletons).to be_empty
        expect(series_groups.keys).to eq ["draft-collins-pfr"]
        expect(series_groups["draft-collins-pfr"].map { |e| e[:ver] }).to eq %w[00 01]
        expect(series_groups["draft-collins-pfr"].map { |e| e[:path] }).to eq paths
      end

      it "normalizes series names containing dots" do
        path = "bibxml-ids/reference.I-D.draft-foo.bar-00.xml"
        expect(Dir).to receive(:[]).with("bibxml-ids/*.xml").and_return([path])

        series_groups, _ = subject.send(:group_draft_paths)
        expect(series_groups.keys).to eq ["draft-foo-bar"]
      end

      it "puts non-versioned files into singleton paths" do
        path = "bibxml-ids/reference.I-D.draft-just-a-name.xml"
        expect(Dir).to receive(:[]).with("bibxml-ids/*.xml").and_return([path])

        series_groups, singletons = subject.send(:group_draft_paths)
        expect(series_groups).to be_empty
        expect(singletons).to eq [path]
      end
    end

    describe "#process_series" do
      it "parses, sorts, links neighbors, serializes, returns index entries" do
        paths_info = [
          { path: "p1", ver: "01", ref: "draft-x-01" },
          { path: "p0", ver: "00", ref: "draft-x-00" }, # intentionally unsorted
        ]
        bib0 = double("bib0", source: [:s0])
        bib1 = double("bib1", source: [:s1])
        allow(bib0).to receive(:version=)
        allow(bib1).to receive(:version=)
        allow(Relaton::Bib::Version).to receive(:new).and_return(:ver)
        expect(subject).to receive(:read_bibxml).with("p0").and_return("x0")
        expect(subject).to receive(:read_bibxml).with("p1").and_return("x1")
        expect(Relaton::Ietf::BibXMLParser).to receive(:parse).with("x0").and_return(bib0)
        expect(Relaton::Ietf::BibXMLParser).to receive(:parse).with("x1").and_return(bib1)

        expect(subject).to receive(:link_neighbor_relations) do |sorted|
          expect(sorted.map { |e| e[:ver] }).to eq %w[00 01]
        end
        expect(subject).to receive(:serialize_and_write).with(bib0).and_return(:r0).ordered
        expect(subject).to receive(:serialize_and_write).with(bib1).and_return(:r1).ordered
        expect(subject).to receive(:build_unversioned_doc) do |series, sorted|
          expect(series).to eq "draft-x"
          expect(sorted.map { |e| e[:ver] }).to eq %w[00 01]
          :unversioned
        end
        expect(subject).to receive(:serialize_and_write).with(:unversioned).and_return(:r2)

        results = subject.send(:process_series, "draft-x", paths_info)
        expect(results).to eq %i[r0 r1 r2]
      end

      it "skips relation linking and un-versioned doc when format is bibxml" do
        bibxml_subject = described_class.new("dir", "bibxml")
        bib = double("bib", source: [])
        allow(bib).to receive(:version=)
        allow(Relaton::Bib::Version).to receive(:new).and_return(:ver)
        expect(bibxml_subject).to receive(:read_bibxml).and_return("x")
        expect(Relaton::Ietf::BibXMLParser).to receive(:parse).and_return(bib)
        expect(bibxml_subject).not_to receive(:link_neighbor_relations)
        expect(bibxml_subject).not_to receive(:build_unversioned_doc)
        expect(bibxml_subject).to receive(:serialize_and_write).with(bib).and_return(:r)

        results = bibxml_subject.send(:process_series, "draft-x", [{ path: "p", ver: "00", ref: "draft-x-00" }])
        expect(results).to eq [:r]
      end

      it "drops nil serialize results from build_unversioned_doc" do
        # build_unversioned_doc returns nil for empty sorted, but process_series
        # always feeds it sorted entries. This guards the .compact on results.
        bib = double("bib", source: [])
        allow(bib).to receive(:version=)
        allow(Relaton::Bib::Version).to receive(:new).and_return(:ver)
        expect(subject).to receive(:read_bibxml).and_return("x")
        expect(Relaton::Ietf::BibXMLParser).to receive(:parse).and_return(bib)
        allow(subject).to receive(:link_neighbor_relations)
        expect(subject).to receive(:serialize_and_write).with(bib).and_return(:r0)
        allow(subject).to receive(:build_unversioned_doc).and_return(nil)
        expect(subject).to receive(:serialize_and_write).with(nil).and_return(nil)

        results = subject.send(:process_series, "draft-x", [{ path: "p", ver: "00", ref: "draft-x-00" }])
        expect(results).to eq [:r0]
      end
    end

    # bibxml files declare encoding='UTF-8' but 125 of the ~122k in the published
    # corpus carry Windows-1252 bytes — smart quotes and accented Latin letters.
    # lutaml raises `InvalidFormatError` on those, and because the drafts path
    # runs under Parallel.map, one raise discards every result from the whole
    # pass: no index, and the already-written files orphaned on disk.
    describe "#read_bibxml" do
      let(:cp1252) { "fixtures/reference.I-D.cp1252-encoded.xml" }

      it "recovers Windows-1252 bytes as their real characters" do
        xml = subject.send(:read_bibxml, cp1252)

        expect(xml.encoding).to eq Encoding::UTF_8
        expect(xml).to be_valid_encoding
        # The point of transcoding rather than scrubbing: `scrub` would put
        # U+FFFD here and lose the apostrophe.
        expect(xml).to include "’"
        expect(xml).not_to include "\uFFFD"
      end

      # A whole-file CP1252 re-decode would mangle this into "MuÃ±oz cafÃ© \u2019"
      # — valid UTF-8, so nothing raises and no skip is recorded. No such file is
      # in today's corpus, but it grows daily and the corruption is silent.
      it "repairs only the bad bytes in a file that is otherwise valid UTF-8" do
        mixed = File.join(Dir.tmpdir, "mixed-encoding.xml")
        File.binwrite mixed, "Mu\xC3\xB1oz caf\xC3\xA9 \x92".b

        expect(subject.send(:read_bibxml, mixed)).to eq "Muñoz café ’"
      ensure
        FileUtils.rm_f mixed
      end

      # CP1252 leaves five byte values undefined; `encode` raises on them, which
      # would cost the whole file rather than the one byte.
      it "does not raise on a byte CP1252 leaves undefined" do
        undef_byte = File.join(Dir.tmpdir, "undef-byte.xml")
        File.binwrite undef_byte, "a\x81b".b

        expect(subject.send(:read_bibxml, undef_byte)).to be_valid_encoding
      ensure
        FileUtils.rm_f undef_byte
      end

      it "leaves a valid UTF-8 file byte-identical" do
        path = "fixtures/rfc.xml"
        # Binary on both sides. `read_bibxml` is byte-verbatim by design, and on
        # Windows a text-mode `File.read` collapses CRLF to LF. Git checks this
        # fixture out with CRLF there (the runner image defaults to
        # `core.autocrlf=true`, and the repo declares no `.gitattributes`), so a
        # text-mode oracle compares against a string the file does not hold.
        xml = subject.send(:read_bibxml, path)

        expect(xml).to eq File.read(path, mode: "rb", encoding: "UTF-8")
        # The oracle above is the same primitive as the method's own read, so it
        # cannot tell a correct read from a differently-spelled one. This pins
        # what it cannot: the early return tags UTF-8 rather than leaving the
        # ASCII-8BIT that `binread` hands back.
        expect(xml.encoding).to eq Encoding::UTF_8
      end

      # The contract the example above asserts, pinned independently of how git
      # checked anything out: `read_bibxml` must not translate line endings. A
      # bibxml file's bytes reach lutaml unchanged, and XML itself normalises
      # CRLF — doing it here would only hide a real difference.
      it "keeps CRLF line endings verbatim" do
        crlf = File.join(Dir.tmpdir, "crlf-bibxml.xml")
        File.binwrite crlf, "<a>\r\n\t<b/>\r\n</a>".b

        expect(subject.send(:read_bibxml, crlf)).to eq "<a>\r\n\t<b/>\r\n</a>"
      ensure
        FileUtils.rm_f crlf
      end

      # The example above covers the early return. The repair path rebuilds the
      # string run by run, which is where a line ending is far likelier to be
      # lost, so cover it too: `scrub` must touch only the invalid run.
      it "keeps CRLF line endings verbatim through the CP1252 repair" do
        crlf_cp1252 = File.join(Dir.tmpdir, "crlf-cp1252-bibxml.xml")
        File.binwrite crlf_cp1252, "<a>\r\n\t<b>caf\xE9</b>\r\n</a>".b

        expect(subject.send(:read_bibxml, crlf_cp1252))
          .to eq "<a>\r\n\t<b>café</b>\r\n</a>"
      ensure
        FileUtils.rm_f crlf_cp1252
      end

      it "parses into a complete record, not a truncated one" do
        bib = Relaton::Ietf::BibXMLParser.parse(subject.send(:read_bibxml, cp1252))

        expect(bib.abstract.first.content.to_s).to include "’"
        expect(bib.title.first.content).to include "Access Network"
      end
    end

    describe "unparseable files" do
      # The file is written but skipped, never fatal — mirroring `parse_pubid`,
      # which lets one bad identifier cost one document rather than the index.
      it "process_singleton returns a marker instead of raising" do
        allow(subject).to receive(:read_bibxml).and_return("<broken")
        allow(Relaton::Ietf::BibXMLParser).to receive(:parse)
          .and_raise(Lutaml::Model::InvalidFormatError.new("xml"))

        result = subject.send(:process_singleton, "bibxml-ids/bad.xml")

        expect(result[:unparsed]).to eq "bibxml-ids/bad.xml"
        expect(result[:error]).to be_a String
      end

      # A failed version must not reach `sorted`: link_neighbor_relations and
      # build_unversioned_doc both dereference `entry[:bib]`.
      it "process_series drops the bad version and keeps the rest" do
        paths = [{ path: "p0", ver: "00", ref: "draft-x-00" },
                 { path: "p1", ver: "01", ref: "draft-x-01" }]
        good = double("bib", source: [])
        allow(good).to receive(:version=)
        allow(subject).to receive(:read_bibxml).and_return("xml")
        allow(Relaton::Ietf::BibXMLParser).to receive(:parse) do
          @n = @n.to_i + 1
          @n == 1 ? raise(Lutaml::Model::InvalidFormatError.new("xml")) : good
        end
        allow(subject).to receive(:serialize_and_write).and_return(:r)
        allow(subject).to receive(:build_unversioned_doc) do |_series, sorted|
          expect(sorted.map { |e| e[:ver] }).to eq %w[01]   # 00 dropped, not nil
          nil
        end

        results = subject.send(:process_series, "draft-x", paths)

        expect(results.select { |r| r.is_a?(Hash) && r[:unparsed] }.map { |r| r[:unparsed] })
          .to eq %w[p0]
        expect(results).to include :r
      end
    end

    describe "#report_unparsed" do
      it "warns once with the count and a sample, not per file" do
        allow(Relaton.logger_pool).to receive(:warn)
        subject.instance_variable_set(:@unparsed, ["a.xml", "b.xml", "c.xml"])

        subject.send(:report_unparsed)

        expect(Relaton.logger_pool).to have_received(:warn)
          .with(/3 file\(s\) skipped.*a\.xml/m, "relaton-ietf").once
      end

      it "says nothing when every file parsed" do
        expect(Relaton.logger_pool).not_to receive(:warn)
        subject.send(:report_unparsed)
      end
    end

    describe "#process_singleton" do
      it "parses, sets version when present, serializes, returns one result" do
        path = "bibxml-ids/reference.I-D.draft-foo-02.xml"
        bib = double("bib")
        allow(bib).to receive(:version=)
        allow(Relaton::Bib::Version).to receive(:new).with(draft: "02").and_return(:ver)
        expect(subject).to receive(:read_bibxml).with(path).and_return("xml")
        expect(Relaton::Ietf::BibXMLParser).to receive(:parse).with("xml").and_return(bib)
        expect(subject).to receive(:serialize_and_write).with(bib).and_return(:result)

        expect(subject.send(:process_singleton, path)).to eq :result
      end

      it "leaves bib.version untouched for non-D.draft files" do
        path = "bibxml-ids/reference.something-else.xml"
        bib = double("bib")
        expect(bib).not_to receive(:version=)
        expect(subject).to receive(:read_bibxml).and_return("xml")
        expect(Relaton::Ietf::BibXMLParser).to receive(:parse).and_return(bib)
        expect(subject).to receive(:serialize_and_write).with(bib).and_return(:result)

        subject.send(:process_singleton, path)
      end
    end

    describe "#link_neighbor_relations" do
      it "links each entry to its immediate predecessor and successor only" do
        relations = Array.new(3) { [] }
        bibs = relations.map { |r| double("bib", relation: r) }
        sorted = bibs.each_with_index.map do |bib, i|
          { ver: format("%02d", i), bib: bib, ref: "draft-x-#{format('%02d', i)}", source: [] }
        end

        subject.send(:link_neighbor_relations, sorted)

        expect(relations[0].map(&:type)).to eq ["updatedBy"]
        expect(relations[1].map(&:type)).to eq %w[updates updatedBy]
        expect(relations[2].map(&:type)).to eq ["updates"]
      end

      it "no-ops for single-version series" do
        bib = double("bib", relation: [])
        sorted = [{ ver: "00", bib: bib, ref: "draft-x-00", source: [] }]
        subject.send(:link_neighbor_relations, sorted)
        expect(bib.relation).to be_empty
      end
    end

    it "build_unversioned_doc uses in-memory bib (no disk round-trip)" do
      last_v = double("last_v", title: :t, abstract: :a,
                                date: :date2, ext: :ext2, source: [:src2])
      sorted = [
        { ver: "00", bib: double("b0"), ref: "draft-collins-pfr-00", source: [:src1] },
        { ver: "01", bib: last_v, ref: "draft-collins-pfr-01", source: [:src2] },
      ]
      expect(Relaton::Bib::Docidentifier).to receive(:new)
        .with(type: "Internet-Draft", content: "draft-collins-pfr", primary: true).and_return(:id)
      expect(Relaton::Bib::Docidentifier).to receive(:new)
        .with(type: "Internet-Draft", content: "draft-collins-pfr-00", primary: true).and_return(:id1)
      expect(Relaton::Bib::Docidentifier).to receive(:new)
        .with(type: "Internet-Draft", content: "draft-collins-pfr-01", primary: true).and_return(:id2)
      expect(Relaton::Bib::Formattedref).to receive(:new).with(content: "draft-collins-pfr-00").and_return(:fref1)
      expect(Relaton::Bib::Formattedref).to receive(:new).with(content: "draft-collins-pfr-01").and_return(:fref2)
      expect(Relaton::Ietf::ItemData).to receive(:new).with(formattedref: :fref1, docidentifier: [:id1], source: [:src1]).and_return(:bibitem1)
      expect(Relaton::Ietf::ItemData).to receive(:new).with(formattedref: :fref2, docidentifier: [:id2], source: [:src2]).and_return(:bibitem2)
      expect(Relaton::Ietf::Relation).to receive(:new).with(type: "includes", bibitem: :bibitem1).and_return(:rel1)
      expect(Relaton::Ietf::Relation).to receive(:new).with(type: "includes", bibitem: :bibitem2).and_return(:rel2)
      expect(Relaton::Bib::Formattedref).to receive(:new).with(content: "draft-collins-pfr").and_return(:fref3)
      expect(Relaton::Ietf::ItemData).to receive(:new).with(
        title: :t, abstract: :a, formattedref: :fref3, docidentifier: [:id], relation: %i[rel1 rel2],
        date: :date2, ext: :ext2, source: [:src2],
      ).and_return(:sbib)
      expect(File).not_to receive(:read)

      expect(subject.send(:build_unversioned_doc, "draft-collins-pfr", sorted)).to eq :sbib
    end

    # An unversioned draft aggregator is synthesised from the versions found on
    # disk — there is no upstream document for it, so date, doctype and source
    # can only come from its constituents. Without this it published with none
    # of the three: undated (so unsorted on the Pages index) and with no
    # document type at all.
    describe "#build_unversioned_doc metadata inheritance" do
      def version(ver, date_at)
        Relaton::Ietf::ItemData.new(
          title: [Relaton::Bib::Title.new(content: "Some draft")],
          docidentifier: [Relaton::Bib::Docidentifier.new(
            type: "Internet-Draft", content: "draft-x-#{ver}", primary: true
          )],
          date: [Relaton::Bib::Date.new(type: "published", at: date_at)],
          source: [Relaton::Bib::Uri.new(type: "src", content: "https://example.com/#{ver}")],
          ext: Relaton::Ietf::Ext.new(
            doctype: Relaton::Ietf::Doctype.new(content: "internet-draft"), flavor: "ietf"
          ),
        )
      end

      let(:sorted) do
        [{ ref: "draft-x-00", bib: version("00", "2020-01-01"), source: [] },
         { ref: "draft-x-01", bib: version("01", "2021-06-01"), source: [] }]
      end

      it "inherits date, ext and source from the newest version" do
        doc = subject.send(:build_unversioned_doc, "draft-x", sorted)

        expect(doc.date.map(&:at).map(&:to_s)).to eq ["2021-06-01"]
        expect(doc.ext.doctype.content).to eq "internet-draft"
        expect(doc.source.map { |s| s.content.to_s }).to eq ["https://example.com/01"]
      end

      it "still carries its own identity, not the version's" do
        doc = subject.send(:build_unversioned_doc, "draft-x", sorted)

        expect(doc.docidentifier.map(&:content)).to eq ["draft-x"]
        expect(doc.formattedref.content).to eq "draft-x"
        expect(doc.relation.map(&:type)).to eq %w[includes includes]
      end

      it "copes with a newest version that has no date or source of its own" do
        bare = Relaton::Ietf::ItemData.new(
          title: [Relaton::Bib::Title.new(content: "Some draft")],
          docidentifier: [Relaton::Bib::Docidentifier.new(
            type: "Internet-Draft", content: "draft-x-01", primary: true
          )],
        )
        doc = subject.send(:build_unversioned_doc, "draft-x",
                           [{ ref: "draft-x-01", bib: bare, source: [] }])

        expect(doc.date).to be_empty
        expect(doc.source).to be_empty
        expect(doc.ext).to be_nil
      end
    end

    it "build_unversioned_doc warns and returns nil when sorted is empty" do
      expect { expect(subject.send(:build_unversioned_doc, "draft-x", [])).to be_nil }
        .to output(/No versions found for draft-x/).to_stderr_from_any_process
    end

    describe "#record_index_entry" do
      it "tracks the file in @files and updates the index" do
        result = { docnumber: "n", file: "dir/x.yaml", index_id: "RFC 1", pubid: pubid("RFC 1") }
        expect(index).to receive(:add_or_update).with(pubid("RFC 1"), "dir/x.yaml")
        subject.send(:record_index_entry, result)
        expect(subject.instance_variable_get(:@files)).to include("dir/x.yaml")
      end

      it "warns when @files already contains the same file" do
        subject.instance_variable_set(:@files, Set.new(["dir/x.yaml"]))
        result = { docnumber: "n", file: "dir/x.yaml", index_id: "RFC 1", pubid: pubid("RFC 1") }
        expect(index).to receive(:add_or_update).with(pubid("RFC 1"), "dir/x.yaml")
        expect { subject.send(:record_index_entry, result) }
          .to output(/File dir\/x.yaml already exists/).to_stderr_from_any_process
      end
    end

    it "create version relation" do
      rel = subject.send(:version_relation, { ref: "draft-collins-pfr-00", source: [] }, "includes")
      expect(rel).to be_instance_of(Relaton::Ietf::Relation)
    end
  end

  context "instance ietf-rfc-entries" do
    subject { described_class.new("dir", "bibxml") }

    before do
      xml = File.read "fixtures/ietf_rfcsubseries.xml"
      allow(Net::HTTP).to receive(:get).and_return(xml)
      allow(Relaton::Ietf::WgNameResolver).to receive(:fetch).and_return({})
    end

    it "initialize fetcher" do
      expect(subject.instance_variable_get(:@ext)).to eq "xml"
      expect(subject.instance_variable_get(:@files)).to be_a Set
      expect(subject.instance_variable_get(:@output)).to eq "dir"
      expect(subject.instance_variable_get(:@format)).to eq "bibxml"
      expect(subject).to be_instance_of(described_class)
    end

    it "fetch data" do
      expect(subject).to receive(:save_doc).with(kind_of(Relaton::Ietf::ItemData)).exactly(2).times
      expect(index).to receive(:save)
      subject.fetch "ietf-rfc-entries"
    end
  end

  describe "#reconcile_output_files" do
    # Workers write from forked processes, so `write_unique` can only take a
    # path of its own on a clash — it cannot know WHICH of the clashing docids
    # deserves the plain name. The parent settles that here, once it can see
    # every docid, so the published filenames do not follow the race.
    subject { described_class.new("dir", "yaml") }

    let(:plain) { "dir/draft-x.yaml" }

    def entry(docid, file, plain_file: plain)
      { docnumber: docid, docid: docid, index_id: docid, file: file, plain_file: plain_file }
    end

    before { allow(File).to receive(:exist?).and_return(true) }

    it "leaves a lone record that already holds its plain path alone" do
      expect(File).not_to receive(:rename)
      results = [entry("draft-x", plain)]
      subject.send(:reconcile_output_files, results)
      expect(results.first[:file]).to eq plain
    end

    it "puts a lone record that fell back to a digest path back on the plain one" do
      # Otherwise the published filename churns and the old file is orphaned.
      digest = subject.send(:digest_output_file, "draft-x")
      expect(File).to receive(:rename).with(digest, plain)
      results = [entry("draft-x", digest)]
      subject.send(:reconcile_output_files, results)
      expect(results.first[:file]).to eq plain
    end

    it "gives the first docid in sort order the plain path and the rest a digest" do
      a = entry("draft-x", plain)
      b = entry("draft-x-", subject.send(:digest_output_file, "draft-x-"))
      allow(File).to receive(:rename)
      subject.send(:reconcile_output_files, [a, b])
      expect(a[:file]).to eq plain
      expect(b[:file]).to eq subject.send(:digest_output_file, "draft-x-")
    end

    it "assigns the same paths whatever order the workers returned in" do
      # `sort_by` is not stable in Ruby, so the key has to break every tie or a
      # re-crawl renames files for no reason.
      forward = [entry("draft-x", plain), entry("draft-x-", "dir/tmp.yaml")]
      backward = [entry("draft-x-", "dir/tmp.yaml"), entry("draft-x", plain)]
      allow(File).to receive(:rename)
      subject.send(:reconcile_output_files, forward)
      described_class.new("dir", "yaml").send(:reconcile_output_files, backward)
      expect(backward.map { |r| [r[:docid], r[:file]] }.sort)
        .to eq forward.map { |r| [r[:docid], r[:file]] }.sort
    end

    it "frees the plain path before the winner claims it" do
      # The loser currently sits on the plain path; renaming the winner first
      # would clobber it.
      winner = entry("draft-x", "dir/tmp.yaml")
      loser = entry("draft-x-", plain)
      digest = subject.send(:digest_output_file, "draft-x-")
      expect(File).to receive(:rename).with(plain, digest).ordered
      expect(File).to receive(:rename).with("dir/tmp.yaml", plain).ordered
      subject.send(:reconcile_output_files, [winner, loser])
    end

    it "collapses two results for ONE docid into one file, and warns" do
      # A genuine duplicate must stay one file: today's behaviour is one file
      # and one warning, and splitting it in two would be a silent change.
      digest = subject.send(:digest_output_file, "draft-x")
      first = entry("draft-x", plain)
      second = entry("draft-x", digest)
      expect(File).to receive(:delete).with(digest)
      expect { subject.send(:reconcile_output_files, [first, second]) }
        .to output(/Duplicate document `draft-x`/).to_stderr_from_any_process
      expect(second[:file]).to eq plain
    end

    it "keeps a duplicate pointed at the winner when a sibling already moved the file" do
      # Two results for ONE docid can carry the SAME file: `write_unique`'s
      # fallback path is keyed on the docid, so two workers that both lost the
      # race to the plain path both land on that docid's digest name. Mixed into
      # a real collision group, the first of them renames that file onto the
      # plain path and the second finds its own file gone. It must still follow
      # the document, or the index gets a row pointing at nothing -- the very
      # failure this pass exists to prevent.
      Dir.mktmpdir do |dir|
        fetcher = described_class.new(dir, "yaml")
        plain = fetcher.output_file("draft-x")
        shared = fetcher.send(:digest_output_file, "draft-x")
        other = fetcher.send(:digest_output_file, "draft-y")
        File.write shared, "x"
        File.write fetcher.output_file("draft-y"), "y"

        dup_a = { docid: "draft-x", file: shared, plain_file: plain }
        dup_b = { docid: "draft-x", file: shared, plain_file: plain }
        distinct = { docid: "draft-y", file: fetcher.output_file("draft-y"), plain_file: plain }

        fetcher.send(:reconcile_output_files, [dup_a, dup_b, distinct])

        expect([dup_a[:file], dup_b[:file]]).to eq [plain, plain]
        expect(distinct[:file]).to eq other
        expect(Dir.children(dir).sort).to eq [File.basename(plain), File.basename(other)].sort
        expect(File.read(plain)).to eq "x"
        expect(File.read(other)).to eq "y"
      end
    end

    it "counts a collision only when the docids differ" do
      allow(File).to receive(:rename)
      subject.send(:reconcile_output_files, [entry("draft-x", plain), entry("draft-x-", "dir/t.yaml")])
      expect(subject.instance_variable_get(:@collisions).size).to eq 1
    end

    it "skips a result with no plain_file rather than renaming to nil" do
      expect(File).not_to receive(:rename)
      results = [entry("draft-x", plain, plain_file: nil)]
      expect { subject.send(:reconcile_output_files, results) }.not_to raise_error
      expect(results.first[:file]).to eq plain
    end

    it "warns and carries on when a rename fails" do
      # A late failure must not throw away a multi-hour crawl.
      digest = subject.send(:digest_output_file, "draft-x")
      allow(File).to receive(:rename).and_raise(Errno::EACCES)
      results = [entry("draft-x", digest)]
      expect { subject.send(:reconcile_output_files, results) }
        .to output(/Could not move/).to_stderr_from_any_process
      expect(results.first[:file]).to eq digest
    end

    it "does not move a file that is not there" do
      allow(File).to receive(:exist?).and_return(false)
      expect(File).not_to receive(:rename)
      subject.send(:reconcile_output_files, [entry("draft-x", "dir/gone.yaml")])
    end
  end

  describe "#report_collisions" do
    subject { described_class.new("dir", "yaml") }

    it "says nothing when no docids collided" do
      expect { subject.send(:report_collisions) }.not_to output.to_stderr_from_any_process
    end

    it "restates the total once, with a sample" do
      # One line for a crawl that writes ~177k records, not one per collision.
      subject.instance_variable_set(:@collisions, [%w[draft-x draft-x-]])
      expect { subject.send(:report_collisions) }
        .to output(/1 filename collision\(s\).*draft-x/m).to_stderr_from_any_process
    end
  end

  context "save doc" do
    subject { described_class.new("dir", "bibxml") }

    let(:entry) do
      did = double("docid", type: "RFC", content: "RFC 1", primary: true)
      double("entry", docnumber: "RFC0001", docidentifier: [did])
    end

    it "skip" do
      expect(File).not_to receive(:write)
      subject.send(:save_doc, nil)
    end

    it "returns the id it wrote under, and the path it intended" do
      # `docid` is NOT `index_id`: `id` falls back through docnumber and
      # formattedref, so on the RFC path they differ ("RFC0001" vs "RFC 1", i.e.
      # stems `rfc0001` and `rfc-1`). reconcile_output_files must key on the id
      # the file was actually written under, or it renames to the wrong name.
      expect(entry).to receive(:to_rfcxml).and_return("<xml/>")
      allow(File).to receive(:write)
      result = subject.send(:serialize_and_write, entry)
      expect(result[:docid]).to eq "RFC0001"
      expect(result[:index_id]).to eq "RFC 1"
      expect(result[:plain_file]).to eq "dir/rfc0001.xml"
      expect(result[:file]).to eq "dir/rfc0001.xml"
    end

    it "reports the path write_unique actually took" do
      # On a clash write_unique returns a path of its own; the index must follow
      # the record, not the name we hoped for.
      expect(entry).to receive(:to_rfcxml).and_return("<xml/>")
      expect(subject).to receive(:write_unique).with("RFC0001", "<xml/>").and_return("dir/other.xml")
      result = subject.send(:serialize_and_write, entry)
      expect(result[:file]).to eq "dir/other.xml"
      expect(result[:plain_file]).to eq "dir/rfc0001.xml"
    end

    it "bibxml" do
      expect(entry).to receive(:to_rfcxml).and_return("<xml/>")
      expect(File).to receive(:write).with("dir/rfc0001.xml", "<xml/>", mode: EXCL, encoding: "UTF-8")
      expect(index).to receive(:add_or_update).with(pubid("RFC 1"), "dir/rfc0001.xml")
      subject.send(:save_doc, entry)
    end

    it "xml" do
      subject.instance_variable_set(:@format, "xml")
      expect(entry).to receive(:to_xml).with(bibdata: true).and_return("<xml/>")
      expect(File).to receive(:write).with("dir/rfc0001.xml", "<xml/>", mode: EXCL, encoding: "UTF-8")
      subject.send(:save_doc, entry)
    end

    it "yaml" do
      subject.instance_variable_set(:@format, "yaml")
      subject.instance_variable_set(:@ext, "yaml")
      expect(entry).to receive(:to_yaml).and_return("---\nid: 123\n")
      expect(File).to receive(:write).with("dir/rfc0001.yaml", "---\nid: 123\n", mode: EXCL, encoding: "UTF-8")
      subject.send(:save_doc, entry)
    end

    it "warn when file exists" do
      subject.instance_variable_set(:@files, Set.new(["dir/rfc0001.xml"]))
      expect(entry).to receive(:to_rfcxml).and_return("<xml/>")
      expect(File).to receive(:write)
        .with("dir/rfc0001.xml", "<xml/>", mode: EXCL, encoding: "UTF-8")
      expect { subject.send(:save_doc, entry) }
        .to output(/File dir\/rfc0001.xml already exists/).to_stderr_from_any_process
    end

    it "downcase file name for ID" do
      subject.instance_variable_set(:@source, "ietf-internet-drafts")
      docid = [
        Relaton::Bib::Docidentifier.new(type: "Internet-Draft", content: "draft-3gpp-collaboration"),
        Relaton::Bib::Docidentifier.new(type: "Internet-Draft", content: "draft-3gpp-collaboration-00", primary: true),
      ]
      id_entry = Relaton::Ietf::ItemData.new(docidentifier: docid)
      expect(id_entry).to receive(:to_rfcxml).and_return("<xml/>")
      expect(File).to receive(:write).with("dir/draft-3gpp-collaboration-00.xml", "<xml/>", mode: EXCL, encoding: "UTF-8")
      expect(index).to receive(:add_or_update)
        .with(pubid("draft-3gpp-collaboration-00"), "dir/draft-3gpp-collaboration-00.xml")
      subject.send(:save_doc, id_entry)
    end

    # The index load is all-or-nothing: `FileIO#deserialize_id` raises on the
    # first id it cannot parse and `#load_index` then rejects the entire index.
    # So a record pubid cannot key must cost that one document, not every
    # lookup. The bibxml anchor form `I-D.foo` is the shape to watch — it is not
    # a pubid grammar. No published id hits this today (176,862/176,862 parse);
    # it guards against upstream drift.
    it "writes a document whose id pubid rejects, but leaves it out of the index" do
      docid = [Relaton::Bib::Docidentifier.new(
        type: "Internet-Draft", content: "I-D.3gpp-collaboration-00", primary: true
      )]
      id_entry = Relaton::Ietf::ItemData.new(docidentifier: docid)
      allow(id_entry).to receive(:to_rfcxml).and_return("<xml/>")
      expect(File).to receive(:write)
        .with("dir/i-d-3gpp-collaboration-00.xml", "<xml/>", mode: EXCL, encoding: "UTF-8")
      expect(index).not_to receive(:add_or_update)

      expect { subject.send(:save_doc, id_entry) }
        .to output(/Not indexing `I-D.3gpp-collaboration-00`/).to_stderr_from_any_process
    end

    it "reports the unindexed total once the crawl finishes" do
      allow(subject).to receive(:fetch_ieft_rfcs)
      subject.send(:record_index_entry,
                   { docnumber: "n", file: "dir/x.yaml", index_id: "I-D.nope-00", pubid: nil })

      expect { subject.fetch "ietf-rfc-entries" }
        .to output(/1 document\(s\) written but not indexed/).to_stderr_from_any_process
    end
  end
end
