# frozen_string_literal: true

require "faraday"

# The W3C flavor reads every record through `w3c_api` -> `lutaml-hal`, whose
# Faraday connection installs `conn.response :json` (see
# `Lutaml::Hal::Client#create_connection`). That middleware parses with
# `::JSON.parse(body, @parser_options || {})` — a POSITIONAL options hash — up
# to and including faraday 2.14.3, the newest release.
#
# json 3.0.0 made those options keyword-only, so the positional hash counts as a
# second positional argument. Every api.w3.org response then dies with
# `ArgumentError: wrong number of arguments (given 2, expected 1)`, which Faraday
# wraps as `Faraday::ParsingError` and `Lutaml::Hal::Client` re-raises as
# `Lutaml::Hal::ParsingError`. Nothing in `Relaton::W3c` can fetch a record.
#
# `relaton.gemspec` therefore holds json below 3. This example is that
# constraint's guard: it reproduces the middleware in isolation, so a bundle
# that resolves an incompatible json fails here with one legible message
# instead of six opaque failures in `data_parser_spec.rb`.
RSpec.describe "Faraday JSON response middleware" do
  # The same middleware and content-type pattern `Lutaml::Hal::Client` builds.
  let(:connection) do
    Faraday.new do |conn|
      conn.response :json, content_type: /\bjson$/
      conn.adapter :test do |stub|
        stub.get("/specifications/webrtc") do
          [200, { "Content-Type" => "application/hal+json;version=1.0" },
           '{"shortname":"webrtc"}']
        end
      end
    end
  end

  it "parses a HAL JSON body instead of raising" do
    expect(connection.get("/specifications/webrtc").body)
      .to eq("shortname" => "webrtc")
  end
end
