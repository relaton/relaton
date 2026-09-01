# frozen_string_literal: true

require "net/http"
require "pubid"
require "uri"
require "yaml"
require "zip"

# Builds `spec/3gpp/fixtures/index-v2.zip`, the offline index the 3GPP suite
# searches against.
#
# The published index has ~88,464 rows. That is not a fixture: it makes the
# suite slow, hides which rows a spec actually depends on, and turns every
# upstream addition into fixture churn. So the fixture is a **curated subset**,
# cut row-for-row from the published index — never hand-written — with one
# document group per matching rule the specs pin. GROUPS documents what each
# group is for.
#
# Rows are copied **verbatim** from `relaton-data-3gpp`'s published
# `index-v2.zip`, so the stored shapes are exactly what
# `Relaton::ThreeGpp::DataFetcher` writes and what the runtime deserializes.
# (Before that index existed the fixture was derived from `index-v1` by
# rendering each id through pubid; that conversion is gone, and `#build`
# refuses a v1 source outright rather than writing a fixture the suite would
# reject.)
#
# Pure logic (row selection) lives here so `spec/tasks/` can unit test it; the
# `rake spec:update_index_3gpp` task is a thin wrapper.
module IndexFixture3gpp
  SOURCE = "https://raw.githubusercontent.com/relaton/relaton-data-3gpp/v2/index-v2.zip"

  # Document groups the specs need, and the rule each one pins. A group is
  # matched on the rendered id prefix up to the qualifier separator, so
  # `TS 23.207` never drags in `TS 23.2071`.
  #
  # The counts are indicative (upstream grows); the specs assert behaviour, not
  # row counts.
  #
  # There is deliberately no "one number, both types" group: measured over all
  # 88,464 published rows, **no document code is carried by both a TS and a
  # TR**. The type rule is still real — a `TR 23.207` reference must not match
  # the `TS 23.207` rows — but it is pinned by a negative lookup rather than by
  # a fixture pair that does not exist upstream.
  GROUPS = {
    "TS 23.207" => "many releases, modern (REL-4 … REL-19) — the version ordering",
    "TS 05.05" => "many releases, legacy 2G (Ph1 … REL-99) — release tokens",
    "TS 04.08" => "the date/release split — pins the known limit",
    "TS 29.198-04-1" => "parts — part of the document code, never ignorable",
    "TR 00.01U" => "suffix — part of the document code, never ignorable",
    "TS 29.215" => "the corpus's only release-less row (`TS 29.215/2.0.0`)",
  }.freeze

  class << self
    # The published artifact holds one YAML entry named after the zip, so
    # derive it rather than hardcoding a version that must stay in sync.
    def entry_name(zip_path)
      "#{File.basename(zip_path, '.zip')}.yaml"
    end

    # Keep only the rows belonging to GROUPS, in the published order.
    #
    # Rows carry a pubid hash `:id`, so selection renders each candidate back
    # to its string form and reuses `keep?`. Rendering all 88,464 would be
    # wasteful, so a cheap `number` test rejects the vast majority first.
    #
    # That pre-filter is a strict SUPERSET of `keep?`, which is what makes it
    # safe: a rendered id is `"<TYPE> <code>"` and `code` always begins with
    # `number`, so anything `keep?` accepts necessarily carries a group's
    # number. Verified over the whole published index — the two-stage filter
    # and rendering every row both select the same 387 rows — and pinned per
    # group by `spec/tasks/index_fixture_3gpp_spec.rb`, because the invariant
    # belongs to the pubid renderer rather than to this file.
    #
    # @param rows [Array<Hash>] published `{ id: Hash, file: String }` rows
    # @return [Array<Hash>]
    def curate(rows)
      numbers = group_numbers
      rows.select do |row|
        id = row[:id]
        numbers.include?(id["number"]) && keep?(render_id(id))
      end
    end

    # A row belongs to a group when its id is the group id, or the group id
    # followed by a qualifier separator (`:` release, `/` version). Anything
    # else — `TS 23.2071`, `TS 29.198-04-2` — is a different document.
    #
    # @param id [String] the rendered identifier
    # @return [Boolean]
    def keep?(id)
      GROUPS.each_key.any? do |group|
        id == group || id.start_with?("#{group}:", "#{group}/")
      end
    end

    # @param id [Hash] a published row's pubid hash
    # @return [String] its rendered identifier, e.g. "TS 29.198-04-1:REL-5/5.0.0"
    def render_id(id)
      ::Pubid::Tgpp::Identifier.from_hash(id).to_s
    end

    # The document numbers GROUPS covers, e.g. "29.198" for `TS 29.198-04-1`.
    # Parsed once from the group ids so the two cannot drift apart.
    #
    # @return [Array<String>]
    def group_numbers
      @group_numbers ||= GROUPS.each_key.map do |group|
        ::Pubid::Tgpp::Identifier.parse(group).number
      end.uniq
    end

    # @param zip_path [String] where to write the fixture
    # @param source [String] published index to cut from
    # @return [Integer] number of rows written
    def build(zip_path, source: SOURCE)
      rows = read_rows(download(source))
      ensure_v2! rows, source

      selected = curate(rows)
      raise "no rows selected from #{source}" if selected.empty?

      write zip_path, selected.to_yaml
      selected.size
    end

    # A v1 index keys rows on a bare String. Writing those under the v2 name
    # would produce a fixture `Relaton::Index` rejects wholesale, so fail here
    # with something that names the cause.
    #
    # Deliberately samples only the first row: the source is one published
    # artifact, written in a single pass, so it is homogeneous. A *mixed* index
    # would slip past this and its String-keyed rows would then be dropped by
    # `curate` rather than raising — `"a string"["number"]` is a substring
    # lookup returning nil, not an error, and `numbers.include?(nil)` is false.
    # That fails safe (rows are omitted, never corrupted), and guarding every
    # row is not worth it for dev-only tooling; noted so the gap is a choice
    # rather than an oversight.
    def ensure_v2!(rows, source)
      return unless rows.first && rows.first[:id].is_a?(String)

      raise "#{source} is a v1 index (string ids); the fixture must be cut " \
            "from the pubid index-v2"
    end

    def download(source)
      resp = Net::HTTP.get_response URI(source)
      raise "HTTP #{resp.code} from #{source}" unless resp.code == "200"

      resp.body
    end

    # The published artifact is a zip holding one YAML entry. Assign into an
    # outer local rather than `return`ing from inside the block — the idiom
    # `Relaton::Index::FileIO#fetch_and_save` already uses for this same API.
    def read_rows(zip_body)
      yaml = nil
      Zip::File.open_buffer(zip_body) do |zip|
        yaml = zip.first.get_input_stream.read
      end
      YAML.safe_load yaml, permitted_classes: [Symbol]
    end

    def write(zip_path, yaml)
      File.delete zip_path if File.exist? zip_path
      Zip::File.open(zip_path, Zip::File::CREATE) do |zip|
        zip.get_output_stream(entry_name(zip_path)) { |f| f.write yaml }
      end
    end
  end
end
