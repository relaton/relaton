# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"

# The canonical conformance fixtures of the relaton-cloud-store work hub.
FIXTURE_ROOT = ENV["RELATON_CLOUD_FIXTURES"] ||
               File.expand_path("../../../TODO.relaton-cloud-store/fixtures", __dir__)

RSpec.describe Relaton::Cloud do
  let(:fixture_dir) { FIXTURE_ROOT }

  def rest_over_fixtures
    manifest_body = File.read(File.join(fixture_dir, "manifest.json"))
    manifest = JSON.parse(manifest_body)
    routes = { "collections/fixtures/manifest" => manifest_body }
    manifest["entries"].each do |e|
      routes["collections/fixtures/entries/#{Lutaml::Store::Source.encode_key(e['key'])}"] =
        File.read(File.join(fixture_dir, e["location"]))
    end
    described_class.source(
      base_url: "https://cloud.test", collection: "fixtures",
      transport: lambda do |uri, _h|
        path = uri.path.sub(%r{\A/}, "")
        routes.key?(path) ? { status_code: 200, headers: {}, body: routes[path] } :
          { status_code: 404, headers: {}, body: "" }
      end
    )
  end

  it "reads a record through the cloud contract" do
    skip "conformance fixtures not found at #{fixture_dir}" unless File.directory?(fixture_dir)

    body = described_class.read("RFC 7231", source: rest_over_fixtures)
    expect(body).to include("RFC7231")
  end

  it "returns typed records with a caller-declared model" do
    skip "conformance fixtures not found at #{fixture_dir}" unless File.directory?(fixture_dir)

    record = Class.new(Lutaml::Model::Serializable) do
      attribute :id, :string
    end
    got = described_class.get("RFC 7231", record, source: rest_over_fixtures)
    expect(got.id).to eq("RFC7231")
  end

  it "resolves a docid reference to the storage key through the manifest" do
    skip "conformance fixtures not found at #{fixture_dir}" unless File.directory?(fixture_dir)

    source = rest_over_fixtures
    # the fixture keys ARE the docids here; both spellings resolve
    expect(described_class.resolve_key("RFC 7231", source: source)).to eq("RFC 7231")
    expect(described_class.resolve_key("rfc 7231", source: source)).to eq("RFC 7231")
    expect(described_class.resolve_key("RFC 9999", source: source)).to be_nil
  end

  it "pulls a whole collection into a GCR-style local package" do
    skip "conformance fixtures not found at #{fixture_dir}" unless File.directory?(fixture_dir)

    into = Dir.mktmpdir
    local = described_class.pull(source: rest_over_fixtures, into: into, collection: "ietf")

    expect(local.keys).to include("RFC 7231")
    expect(File).to exist(File.join(into, "ietf", "manifest.json"))
    # the pulled package reads back as an ordinary local source
    same = described_class.local(File.join(into, "ietf"))
    expect(same.read("RFC 7231")).to include("RFC7231")
  end

  it "builds a read-through repository over the cloud and a local cache" do
    skip "conformance fixtures not found at #{fixture_dir}" unless File.directory?(fixture_dir)

    source = rest_over_fixtures
    cache = File.join(Dir.mktmpdir, "cache")
    repo = described_class.repository(
      base_url: "https://cloud.test", collection: "fixtures", cache_path: cache,
      transport: source.options[:transport]
    )
    expect(repo.read("RFC 7231")).to include("RFC7231")
  end
end
