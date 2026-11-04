# frozen_string_literal: true

require_relative "../spec_helper"
require "json"
require "relaton/bib"
require "relaton/bib/hash_parser_v1"

# The Ruby executor for the shared citation rendering corpus
# (citation-testsuite): the same records and golden strings the relaton-ts
# executor (test/golden_render.test.ts) asserts. The goldens are
# style-family keyed; the packs render them (iso690 → author-date).
RSpec.describe "citation render corpus (citation-testsuite)" do
  let(:fixture_dir) do
    ENV["CITATION_TESTSUITE_DIR"] ||
      File.expand_path("../../../citation-testsuite", __dir__)
  end

  # Loaded at group-definition time: the corpus is fixture data, not
  # per-example state.
  def self.load_cases
    dir = ENV["CITATION_TESTSUITE_DIR"] ||
          File.expand_path("../../../citation-testsuite", __dir__)
    rec_dir = File.join(dir, "records")
    return [] unless Dir.exist?(rec_dir)

    Dir.children(rec_dir).sort.map do |f|
      name = f.delete_suffix(".json")
      record = JSON.parse(File.read(File.join(rec_dir, f)))
      golden = JSON.parse(File.read(File.join(dir, "golden", "#{name}.json")))
      [name, record, golden]
    end
  end

  cases = load_cases

  PACKS = { "iso690" => "author-date", "chicago" => "chicago", "apa" => "apa",
            "mla" => "mla" }.freeze

  # The corpus's loose shapes to the v1 hash dialect: person names carry
  # bare given/surname strings, dates use the `at` key.
  def adapt(record)
    record = deep_dup(record)
    Array(record["date"]).each do |d|
      # The v1 dialect: HashParserV1 maps `value` to the model's `at`.
      d["value"] = d.delete("at") if d.is_a?(Hash) && d["at"]
    end
    Array(record["contributor"]).each do |c|
      person = c.is_a?(Hash) && c["person"]
      next unless person
      name = person["name"]
      next unless name.is_a?(Hash) && name["surname"]
      surname = name["surname"]
      name["surname"] = { "content" => surname } unless surname.is_a?(Hash)
      if name["given"]
        given = name.delete("given")
        name["forename"] = [{ "content" => given }]
      end
    end
    record
  end

  def deep_dup(obj)
    case obj
    when Hash then obj.to_h { |k, v| [k, deep_dup(v)] }
    when Array then obj.map { |v| deep_dup(v) }
    else obj
    end
  end

  before do
    skip "no citation-testsuite checkout at #{fixture_dir}" if cases.empty?
  end


  it "has the three house-style families in every golden" do
    cases.each do |name, _, golden|
      expect(golden.keys.sort).to eq(%w[apa chicago iso690 mla])
    end
  end

  # Parity deltas against the TS-executed goldens, each a tracked item:
  # the engine renders structurally-correct output with a formatting or
  # slot-resolution difference; reconciling is the render-parity backlog.
  DELTA_NOTES = {}.freeze

  cases.each do |name, record, golden|
    PACKS.each do |family, pack|
      group = "#{name} renders in #{family} (#{pack})"
      if (note = DELTA_NOTES["#{name}/#{family}"])
        xdescribe group do
          xit "parity delta: #{note}"
        end
        next
      end
      it group do
        model = Relaton::Bib::Item.from_hash(
          Relaton::Bib::HashParserV1.hash_to_bib(adapt(record)),
        )
        expect(Relaton::Render::Iso690::Renderer.render(model, style: pack))
          .to eq(golden[family])
      end
    end
  end
end
