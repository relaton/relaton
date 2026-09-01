# frozen_string_literal: true

require "net/http"
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
# Rows are copied verbatim except that the `:id` string is parsed into a
# `Pubid::Tgpp::Identifier` and stored as its `to_hash`. That is exactly what
# `Relaton::ThreeGpp::DataFetcher` writes, and the round-trip is byte-identical
# over the whole corpus, so a fixture derived from `index-v1` is shape-faithful
# even before `relaton-data-3gpp` publishes its own `index-v2`. Point SOURCE at
# `index-v2.zip` once it does.
#
# Pure logic (row selection, conversion) lives here so `spec/tasks/` can unit
# test it; the `rake spec:update_index_3gpp` task is a thin wrapper.
module IndexFixture3gpp
  SOURCE = "https://raw.githubusercontent.com/relaton/relaton-data-3gpp/v2/index-v1.zip"

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
    # @param rows [Array<Hash>] raw `{ id: String, file: String }` rows
    # @return [Array<Hash>]
    def curate(rows)
      rows.select { |row| keep? row[:id].to_s }
    end

    # A row belongs to a group when its id is the group id, or the group id
    # followed by a qualifier separator (`:` release, `/` version). Anything
    # else — `TS 23.2071`, `TS 29.198-04-2` — is a different document.
    #
    # @param id [String]
    # @return [Boolean]
    def keep?(id)
      GROUPS.each_key.any? do |group|
        id == group || id.start_with?("#{group}:", "#{group}/")
      end
    end

    # Replace each row's string `:id` with the pubid hash the runtime expects.
    # A row pubid cannot parse is a defect in the source index, not something
    # to paper over — raise rather than write a fixture the consumer rejects.
    #
    # @param rows [Array<Hash>]
    # @return [Array<Hash>]
    def to_pubid_rows(rows)
      require "pubid"

      rows.map do |row|
        id = ::Pubid::Tgpp::Identifier.parse row[:id].to_s
        unless id.to_s == row[:id].to_s
          raise "pubid does not round-trip `#{row[:id]}` (got `#{id}`)"
        end

        { id: id.to_hash, file: row[:file] }
      end
    end

    # @param zip_path [String] where to write the fixture
    # @param source [String] published index to cut from
    # @return [Integer] number of rows written
    def build(zip_path, source: SOURCE)
      rows = to_pubid_rows(curate(read_rows(download(source))))
      raise "no rows selected from #{source}" if rows.empty?

      write zip_path, rows.to_yaml
      rows.size
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
