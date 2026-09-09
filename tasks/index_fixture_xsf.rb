# frozen_string_literal: true

require "net/http"
require "pubid"
require "uri"
require "yaml"
require "zip"

# Builds `spec/xsf/fixtures/index-v2.zip`, the offline index the XSF suite
# searches against.
#
# The whole published index (~518 rows), not a curated subset: XSF publishes one
# row per XEP with no editions or revisions, so keeping all of them costs
# nothing and removes any question of which rows a spec depends on.
#
# `relaton-data-xsf` still publishes only `index-v1`, whose `:id` is a bare
# string. Each id is therefore parsed into a `Pubid::Xsf::Identifier` and stored
# as its `to_hash` — exactly what `Relaton::Xsf::DataFetcher` now writes, so a
# fixture derived this way is shape-faithful before the data repo has its own
# v2. **Point SOURCE at `index-v2.zip` and delete `to_pubid_rows` once it
# publishes one** (see tasks/index_fixture_ogc.rb for how that ended up).
#
# Two published rows are dropped on the way: `XEP README` and `XEP xxxx` are the
# XMPP repo's readme and template, not documents. One unparseable row makes
# `Relaton::Index` declare the whole file corrupt and hand back an EMPTY index
# (measured: 518 good rows plus one of these loads as 0), so they cannot be
# carried — the producer's `DataFetcher#add_to_index` skips them for the same
# reason.
#
# Pure logic lives here so `spec/tasks/` can unit test it; the
# `rake spec:update_index_xsf` task is a thin wrapper.
module IndexFixtureXsf
  SOURCE = "https://raw.githubusercontent.com/relaton/relaton-data-xsf/v2/index-v1.zip"

  class << self
    # The published artifact holds one YAML entry named after the zip, so
    # derive it rather than hardcoding a version that must stay in sync.
    def entry_name(zip_path)
      "#{File.basename(zip_path, '.zip')}.yaml"
    end

    # Convert v1 string ids to the pubid hashes the runtime deserializes.
    #
    # A row pubid cannot parse is dropped with a warning rather than aborting:
    # the two non-documents in the published index (`XEP README`, `XEP xxxx`)
    # are exactly what this skips, and carrying them would make the fixture
    # unloadable.
    #
    # @param rows [Array<Hash>] published `{ id: String, file: String }` rows
    # @return [Array<Hash>] `{ id: Hash, file: String }` rows
    #
    def to_pubid_rows(rows)
      rows.filter_map do |row|
        { id: ::Pubid::Xsf::Identifier.parse(row[:id].to_s).to_hash, file: row[:file] }
      rescue StandardError => e
        warn "skipping #{row[:id].inspect}: #{e.message}"
        nil
      end
    end

    # @param zip_path [String] where to write the fixture
    # @param source [String] published index to cut from
    # @return [Integer] number of rows written
    def build(zip_path, source: SOURCE)
      rows = read_rows(download(source))
      selected = rows.first && rows.first[:id].is_a?(String) ? to_pubid_rows(rows) : rows
      raise "no rows selected from #{source}" if selected.empty?

      write zip_path, selected.to_yaml
      selected.size
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
