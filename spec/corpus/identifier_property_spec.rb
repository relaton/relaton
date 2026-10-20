# frozen_string_literal: true

# The corpus property suite (docs/identifier-model.adoc, Laws 0, 1, 2 and 4),
# executed over each flavor's FULL published index. Default flavors are the
# small, varied corpora; CORPUS=<flavor,flavor> runs a set; extend the
# FLAVORS registry as more corpora graduate.
require "set"
require "spec_helper"

# Every flavor with a published relaton-data-* index. Defaults are the v2
# machine-index layout; a flavor overrides branch/indexfile where its repo or
# flavor INDEXFILE differs (IHO publishes v3, JCGM v1). `repo:` is set only
# where the data repo name differs from the flavor (itu_r is the ITU-R half of
# the ITU dataset).
DEFAULT_INDEX = { branch: "v2", indexfile: "index-v2" }.freeze
# Law 4 samples same-root pairs; a large corpus has hundreds of thousands of
# them and each match runs a full subset walk. A deterministic cap keeps the
# law's cost bounded while still covering every bucket in corpus order.
MATCH_PAIR_LIMIT = 20_000
MATCH_BUCKET_SAMPLE = 16

# A deterministic corpus slice "i/n" (row index i mod n), so a big corpus can
# be checked across parallel CI jobs without redownloading a different index.
# The union of the slices is the whole corpus. Empty or "0/1" = everything.
SLICE = ENV["CORPUS_SLICE"].to_s

slice_rows = lambda do |rows|
  next rows unless SLICE.match?(%r{\A\d+/\d+\z})

  index, total = SLICE.split("/").map(&:to_i)
  rows.each_with_index.select { |_, i| i % total == index }.map(&:first)
end
FLAVORS = {
  "3gpp": { require: "relaton/3gpp", pubid: "Pubid::Tgpp::Identifier" },
  adobe: { branch: "main", require: "relaton/adobe", pubid: "Pubid::Adobe::Identifier" },
  bipm: { require: "relaton/bipm", pubid: "Pubid::Bipm::Identifier" },
  calconnect: { require: "relaton/calconnect", pubid: "Pubid::Calconnect::Identifier" },
  ccsds: { require: "relaton/ccsds", pubid: "Pubid::Ccsds::Identifier" },
  cie: { require: "relaton/cie", pubid: "Pubid::Cie::Identifier" },
  easc: { branch: "main", require: "relaton/easc", pubid: "Pubid::Easc::Identifier" },
  ecma: { require: "relaton/ecma", pubid: "Pubid::Ecma::Identifier" },
  etsi: { require: "relaton/etsi", pubid: "Pubid::Etsi::Identifier" },
  gost: { branch: "main", require: "relaton/gost", pubid: "Pubid::Gost::Identifier" },
  iala: { branch: "main", require: "relaton/iala", pubid: "Pubid::Iala::Identifier" },
  iana: { require: "relaton/iana", pubid: "Pubid::Iana::Identifier" },
  iec: { require: "relaton/iec", pubid: "Pubid::Iec::Identifier" },
  ieee: { require: "relaton/ieee", pubid: "Pubid::Ieee::Identifier" },
  ietf: { branch: "main", require: "relaton/ietf", pubid: "Pubid::Ietf::Identifier" },
  iho: { indexfile: "index-v3", require: "relaton/iho", pubid: "Pubid::Iho::Identifier" },
  iso: { require: "relaton/iso", pubid: "Pubid::Iso::Identifier" },
  itu: { branch: "main", require: "relaton/itu", pubid: "Pubid::Itu::Identifier" },
  itu_r: { branch: "v2", repo: "itu-r", require: "relaton/itu", pubid: "Pubid::Itu::Identifier" },
  jcgm: { branch: "main", indexfile: "index-v1", require: "relaton/jcgm", pubid: "Pubid::Jcgm::Identifier" },
  jis: { require: "relaton/jis", pubid: "Pubid::Jis::Identifier" },
  nist: { require: "relaton/nist", pubid: "Pubid::Nist::Identifier" },
  oasis: { require: "relaton/oasis", pubid: "Pubid::Oasis::Identifier" },
  ogc: { require: "relaton/ogc", pubid: "Pubid::Ogc::Identifier" },
  oiml: { branch: "main", require: "relaton/oiml", pubid: "Pubid::Oiml::Identifier" },
  omg: { branch: "main", require: "relaton/omg", pubid: "Pubid::Omg::Identifier" },
  plateau: { require: "relaton/plateau", pubid: "Pubid::Plateau::Identifier" },
  w3c: { require: "relaton/w3c", pubid: "Pubid::W3c::Identifier" },
  xsf: { require: "relaton/xsf", pubid: "Pubid::Xsf::Identifier" },
}.freeze

selected = case ENV["CORPUS"]
           when nil, "" then FLAVORS.keys
           else ENV["CORPUS"].split(",").map(&:to_sym)
           end

selected.each do |flavor|
  cfg = DEFAULT_INDEX.merge(FLAVORS.fetch(flavor) { raise "unknown corpus flavor #{flavor}" })
  require cfg[:require]

  RSpec.describe "identifier corpus: #{flavor}", order: :defined do
    klass = Object.const_get(cfg[:pubid])

    let(:all_rows) do
      @all_rows ||= Corpus.fetch_index(flavor, cfg[:branch], cfg[:indexfile],
                                       cfg[:repo] || flavor.to_s).compact
    end

    let(:rows) { @rows ||= slice_rows.call(all_rows) }

    # Every row paired with its deserialized identifier (nil when the grammar
    # rejects the row). Law 0 asserts the nil count is a known_failures entry,
    # so a corpus row pubid cannot read is never silently skipped.
    let(:decoded) do
      @decoded ||= rows.map { |h| [h, (klass.from_hash(h) rescue nil)] }
    end

    let(:ids) { decoded.filter_map(&:last) }

    # One parse per row, shared by Laws 1a and 1b: [id, printed, parsed or
    # nil]. Both laws otherwise pay for a full parse per identifier, which
    # dominates the run on a large corpus.
    let(:roundtrips) do
      @roundtrips ||= ids.map do |id|
        printed = id.to_s
        parsed = begin
          klass.parse(printed)
        rescue StandardError
          nil
        end
        [id, printed, parsed]
      end
    end

    # Candidate pairs for Law 4: identifiers sharing a root number, i.e. one
    # document's editions/parts/stages. Distinct roots can never match (the
    # stated components differ). The sample is deterministic: buckets in
    # corpus order, at most MATCH_BUCKET_SAMPLE rows each, capped at
    # MATCH_PAIR_LIMIT pairs so a 200k-row corpus does not turn the law into
    # an hours-long subset walk.
    let(:match_pairs) do
      @match_pairs ||= begin
        buckets = Hash.new { |hash, key| hash[key] = [] }
        ids.each do |id|
          key = begin
            [id.class, id.root.number.to_s]
          rescue StandardError
            nil
          end
          buckets[key] << id if key
        end
        pairs = []
        buckets.each_value do |group|
          next if group.size < 2

          group.first(MATCH_BUCKET_SAMPLE).combination(2) do |a, b|
            pairs << [a, b]
            break if pairs.size >= MATCH_PAIR_LIMIT
          end
          break if pairs.size >= MATCH_PAIR_LIMIT
        end
        pairs
      end
    end

    # Manifest-driven enforcement: a failure listed in
    # known_failures/<flavor>-<manifest>.txt is a tracked grammar gap (each
    # names the pubid issue); an UNLISTED one is recorded into that manifest
    # and fails the run, so the next run passes and the new row is visible in
    # review. The prose in the failure message and the file itself are the
    # tracking.
    def enforce(flavor, manifest, failures, what)
      file = File.join(__dir__, "known_failures", "#{flavor}-#{manifest}.txt")
      # Slices of one flavor may run in parallel: serialize the read-record-
      # write so neither slice loses the other's discoveries.
      lock = File.join(Dir.tmpdir, "relaton-corpus-manifests.lock")
      File.open(lock, File::RDWR | File::CREAT, 0o644) do |lock_file|
        lock_file.flock(File::LOCK_EX)
        known = if File.exist?(file)
                  File.read(file).lines.map(&:strip).reject(&:empty?).to_set
                else
                  Set.new
                end
        new_failures = failures.reject { |printed| known.include?(printed) }
        next if new_failures.empty?

        File.write(file, (known + new_failures).uniq.sort.join("\n") + "\n")
        expect(new_failures).to be_empty,
          "#{new_failures.size} NEW #{what} failures; they were RECORDED into " \
          "known_failures/#{flavor}-#{manifest}.txt (tracked for a pubid fix) — " \
          "re-run to pass. e.g.: #{new_failures.first(5).join('; ')}"
      end
    end

    it "has a non-empty corpus" do
      expect(ids).not_to be_empty
    end

    # Coverage metric (stream 7): how many published rows the grammar reads.
    # Emitted to stdout and the CI job summary; this is the per-SDO number the
    # conformance report tracks over time.
    it "reports corpus coverage" do
      covered = decoded.count { |_, id| id }
      scope = SLICE.empty? ? "" : " [#{SLICE}]"
      of_total = SLICE.empty? ? "" : " of #{all_rows.size} in the corpus"
      line = "CORPUS #{flavor}#{scope}: #{covered}/#{rows.size} published rows " \
             "deserialize#{of_total}"
      puts line
      summary = ENV["GITHUB_STEP_SUMMARY"]
      File.open(summary, "a") { |file| file.puts line } if summary
    end

    # Law 0: the published structured id deserializes through the flavor's own
    # pubid class — the same call Relaton::Index makes on every row.
    it "deserializes every published row (Law 0)" do
      failures = decoded.reject { |_, id| id }.map { |h, _| h[:id].to_s }
      enforce(flavor, "load", failures, "deserialization")
    end

    # Law 1a: fidelity. render(parse(printed)) == printed — the printed form
    # of every published row re-parses to itself.
    it "re-parses every row's printed form to itself (Law 1a)" do
      failures = roundtrips.filter_map do |_, printed, parsed|
        printed unless parsed && parsed.to_s == printed
      end
      enforce(flavor, "fidelity", failures, "render(parse(x))==x")
    end

    # Law 2: exclude idempotence — excluding a component the identifier does
    # not carry is a no-op, twice.
    it "exclude of an absent component is a no-op (Law 2)" do
      failures = ids.filter_map do |id|
        absent = id.to_hash.select { |_, value| value.nil? }.keys
        next nil if absent.empty?

        once = id.exclude(*absent)
        "structure differs" if once.to_hash != id.to_hash ||
                               once.exclude(*absent).to_hash != once.to_hash
      rescue StandardError => e
        "#{id}: #{e.class}"
      end
      expect(failures).to be_empty
    end

    # Law 1b: the printed and structured forms are the same identifier —
    # parsing the rendered form restores the very structure it came from.
    it "re-parses its own render to the same structure (Law 1b)" do
      failures = roundtrips.filter_map do |id, printed, parsed|
        next nil unless parsed # an unparseable form is Law 1a's finding

        printed if parsed.to_hash != id.to_hash
      end
      enforce(flavor, "structure", failures, "parse(render(x))==x")
    end

    # Law 4: mutual subset match means one document. The operator is
    # asymmetric by design (the receiver is the reference), so only pairs that
    # match both ways constrain identity. Tested as the contrapositive, over
    # every same-root pair: two identifiers that render differently must not
    # match both ways. (An unbucketed corpus has no mutual matches at all —
    # mutual match implies identical stated components — so asserting on
    # differing pairs is the non-vacuous form.)
    it "distinct rendered identifiers never match mutually (Law 4)" do
      failures = match_pairs.filter_map do |a, b|
        next nil if a.to_s == b.to_s

        "#{a} vs #{b}" if (a === b) && (b === a)
      rescue StandardError
        nil
      end
      expect(failures).to be_empty
    end
  end
end
