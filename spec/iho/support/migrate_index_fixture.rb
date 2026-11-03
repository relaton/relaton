# frozen_string_literal: true

# One-shot migration of spec/iho/fixtures/index-v3.zip to the pubid 2.0.5
# IHO component model (relaton#440). The committed rows were serialized by
# the pre-#440 generator; 2.0.5's from_hash drops the old keys, so stated
# editions stopped matching. Key-level remap, rendered ids untouched:
#   version (no component)          -> edition
#   version beside supplement/part/ -> <component>_edition
#     annex/appendix/volume
#   year on a volume-locator series -> volume (the yearbook year IS a
#                                     volume; relaton#440 unified them)
#   volume / issue / subdivisions   -> unchanged
# Run from spec/iho:
#   cd spec/iho && bundle exec ruby support/migrate_index_fixture.rb
# Delete this file once relaton-data-iho round 2 republishes and the
# fixture is refreshed from the live index.
require "yaml"
require "zip"
require "fileutils"

ZIP = File.expand_path("../fixtures/index-v3.zip", __dir__)

yaml = Zip::File.open(ZIP) { |z| z.first.get_input_stream.read }
rows = YAML.unsafe_load(yaml)

remapped = 0
migrated = rows.map do |row|
  id = row[:id]
  next row unless id.is_a?(Hash)

  out = {}
  id.each do |k, v|
    key = k.to_s
    case key
    when "version"
      component = %w[supplement part annex appendix volume].find { |c| id[c.to_sym] }
      key = component ? "#{component}_edition" : "edition"
    when "year"
      key = "volume" unless id[:volume]
    end
    remapped += 1 if out[key.to_sym] != v || key != k.to_s
    out[key.to_sym] = v
  end
  row.merge(id: out)
end

Zip::OutputStream.open(ZIP + ".tmp") do |zio|
  zio.put_next_entry("index-v3.yaml")
  zio.write(YAML.dump(migrated))
end
FileUtils.mv(ZIP + ".tmp", ZIP)
puts "migrated #{migrated.size} rows (#{remapped} keys remapped) -> #{ZIP}"
