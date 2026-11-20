require "webmock/rspec"
require "tmpdir"
require "relaton/eu"

# The offline index the consumer specs search: `fixtures/index-v2.yaml`, the
# index that `Relaton::Eu::DataFetcher` writes from the CELLAR fixtures
# (`fixtures/cellar/`), seeded straight into the Relaton::Index pool so no
# example reads the Pages site. (The SAE pattern; see spec/sae/support.)
#
# Built with `pubid_class:`, as the runtime builds it: without it the rows stay
# raw hashes and `Type#search` stops narrowing.
module EuIndexFixture
  def self.index_type
    @index_type ||= build
  end

  def self.build
    src = File.join(__dir__, "..", "fixtures", "#{Relaton::Eu::INDEXFILE}.yaml")
    file = File.join(Dir.mktmpdir("relaton-eu-spec"), "#{Relaton::Eu::INDEXFILE}.yaml")
    File.write file, File.read(src, encoding: "UTF-8"), encoding: "UTF-8"
    type = Relaton::Index::Type.new(:eu, file: file, pubid_class: ::Pubid::Eu::Identifier)
    type.index # deserialize and sort once, offline
    type.define_singleton_method(:actual?) do |**args|
      args.key?(:pages_url) || args.key?(:url)
    end
    type
  end
end

# Answer CELLAR from `fixtures/cellar/<year>.json`: the real answer of
# `Cellar::QUERY` for that year, narrowed to a few works. A page request gets
# the slice its `LIMIT` and `OFFSET` name; a `COUNT_QUERY` gets the number of
# rows in the fixture (that answer is built here, in the shape CELLAR gives).
# A year with no fixture has no rows.
module CellarStub
  FIXTURES = File.join(__dir__, "..", "fixtures", "cellar")

  def self.rows(year)
    file = File.join(FIXTURES, "#{year}.json")
    return [] unless File.exist?(file)

    JSON.parse(File.read(file, encoding: "UTF-8")).dig("results", "bindings")
  end

  def self.body(bindings)
    { "head" => { "vars" => [] }, "results" => { "bindings" => bindings } }.to_json
  end

  # A query for the works changed since a time (`Cellar#each_modified_row`)
  # names no year; it gets the rows of `modified`, which receives that time.
  #
  # @param rows [Proc] year -> bindings, to serve other rows than the fixture
  # @param modified [Proc] since (String) -> bindings
  def self.response(request, rows: method(:rows), modified: ->(_since) { [] })
    query = URI.decode_www_form(request.uri.query).to_h.fetch("query")
    since = query[/\?modified >= "([^"]+)"/, 1]
    all = since ? modified.call(since) : rows.call(query[/resource_legal_year "(\d{4})"/, 1])
    bindings = if query.include?("COUNT(DISTINCT ?celex)")
                 [{ "n" => { "type" => "literal", "value" => all.size.to_s } }]
               else
                 all.drop(query[/OFFSET (\d+)/, 1].to_i).first(query[/LIMIT (\d+)/, 1].to_i)
               end
    { status: 200, body: body(bindings),
      headers: { "Content-Type" => "application/sparql-results+json" } }
  end

  def stub_cellar
    stub_request(:get, /\A#{Regexp.escape Relaton::Eu::Cellar::URL}\?/o)
      .to_return { |req| CellarStub.response(req) }
  end
end

RSpec.configure do |config|
  config.include CellarStub

  config.before(:each) do |example|
    unless example.metadata[:no_index_fixture]
      Relaton::Index.pool.instance_variable_get(:@pool)[:EU] =
        EuIndexFixture.index_type
    end
    WebMock.reset!
    WebMock.disable_net_connect!
    # The crawler waits one second between CELLAR requests.
    allow_any_instance_of(Relaton::Core::Pacer).to receive(:wait)
  end

  config.after(:each, :no_index_fixture) do
    Relaton::Index.pool.instance_variable_get(:@pool).delete(:EU)
  end
end
