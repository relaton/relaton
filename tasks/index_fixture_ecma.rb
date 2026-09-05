# frozen_string_literal: true

require "net/http"
require "pubid"
require "uri"
require "yaml"
require "zip"

# Builds `spec/ecma/fixtures/index-v2.zip`, the offline index the ECMA suite
# searches against.
#
# Like OGC's and unlike 3GPP's, this fixture is the **whole** published index,
# not a curated subset: ECMA publishes 804 rows, small enough that keeping all
# of them costs nothing and removes any question of which rows a spec depends
# on.
#
# Rows are copied **verbatim** from `relaton-data-ecma`'s published
# `index-v2.zip`, so the stored shapes are exactly what
# `Relaton::Ecma::DataFetcher` writes and what the runtime deserializes.
#
# Pure logic lives here so `spec/tasks/` can unit test it; the
# `rake spec:update_index_ecma` task is a thin wrapper.
module IndexFixtureEcma
  SOURCE = "https://raw.githubusercontent.com/relaton/relaton-data-ecma/v2/index-v2.zip"

  class << self
    # The published artifact holds one YAML entry named after the zip, so
    # derive it rather than hardcoding a version that must stay in sync.
    def entry_name(zip_path)
      "#{File.basename(zip_path, '.zip')}.yaml"
    end

    # A v1 index keys rows on a bare Hash (`{id:, ed:, vol:}`); a v2 row keys on
    # a pubid hash carrying `_type`. Writing v1 rows under the v2 name would
    # produce a fixture `Relaton::Index` rejects wholesale, so fail here with
    # something that names the cause. Samples only the first row: the source is
    # one published artifact written in a single pass, so it is homogeneous.
    def ensure_v2!(rows, source)
      return if rows.first && rows.first[:id].is_a?(Hash) && rows.first[:id]["_type"]

      raise "#{source} is not a pubid index-v2; the fixture must be cut from " \
            "the published index-v2"
    end

    # @param zip_path [String] where to write the fixture
    # @param source [String] published index to cut from
    # @return [Integer] number of rows written
    def build(zip_path, source: SOURCE)
      rows = read_rows(download(source))
      raise "no rows in #{source}" if rows.empty?

      ensure_v2! rows, source
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
