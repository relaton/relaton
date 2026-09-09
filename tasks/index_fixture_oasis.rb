# frozen_string_literal: true

require "net/http"
require "pubid"
require "uri"
require "yaml"
require "zip"

# Builds `spec/oasis/fixtures/index-v2.zip`, the offline index the OASIS suite
# searches against.
#
# Like OGC's, this fixture is the **whole** published index rather than a
# curated subset: OASIS publishes 605 rows, small enough that keeping all of
# them costs nothing and removes any question of which rows a spec depends on.
#
# Rows are copied **verbatim** from `relaton-data-oasis`'s published
# `index-v2.zip` (the `v2` branch, the same one `Bibliography::ENDPOINT`
# reads), so the stored shapes are exactly what `Relaton::Oasis::DataFetcher`
# writes and what the runtime deserializes.
#
# Pure logic lives here so `spec/tasks/` can unit test it; the
# `rake spec:update_index_oasis` task is a thin wrapper.
module IndexFixtureOasis
  SOURCE = "https://raw.githubusercontent.com/relaton/relaton-data-oasis/" \
           "refs/heads/v2/index-v2.zip"

  class << self
    # The published artifact holds one YAML entry named after the zip, so
    # derive it rather than hardcoding a version that must stay in sync.
    def entry_name(zip_path)
      "#{File.basename(zip_path, '.zip')}.yaml"
    end

    # A v1 index keys rows on a bare String. Writing those under the v2 name
    # would produce a fixture `Relaton::Index` rejects wholesale, so fail here
    # with something that names the cause. Samples only the first row: the
    # source is one published artifact written in a single pass, so it is
    # homogeneous.
    def ensure_v2!(rows, source)
      return unless rows.first && rows.first[:id].is_a?(String)

      raise "#{source} is a v1 index (string ids); the fixture must be cut " \
            "from the pubid index-v2"
    end

    # @param zip_path [String] where to write the fixture
    # @param source [String] published index to cut from
    # @return [Integer] number of rows written
    def build(zip_path, source: SOURCE)
      rows = read_rows(download(source))
      ensure_v2! rows, source
      raise "no rows in #{source}" if rows.empty?

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
