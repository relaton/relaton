# frozen_string_literal: true

require "faraday"
require "lutaml/hal"

# The W3C flavor reads every record through `w3c_api` -> `lutaml-hal`. The
# JSON parse lives in `Lutaml::Hal::Client#parse_json_body` (yeptris) since
# lutaml-hal#25/#26 — the Faraday `response :json` middleware is gone from
# both the default connection and w3c_api's injected one, because it parses
# with `::JSON.parse(body, @parser_options || {})`, a POSITIONAL options hash
# json 3.0 rejects. The gemspec carries no json pin for that reason.
#
# This spec is that removal's guard: if either stack starts installing the
# JSON middleware again — or the parameterized content-type split drifts —
# a bundle that resolves json 3 fails here with one legible message instead
# of `ArgumentError` inside every api.w3.org response.
RSpec.describe "W3C stack JSON parsing" do
  # The connection lutaml-hal builds by default.
  let(:client) { Lutaml::Hal::Client.new(api_url: "https://api.example.org") }

  it "installs no JSON middleware on the default connection" do
    expect(client.connection.builder.handlers).not_to include(:json)
  end

  it "parses a parameterized HAL JSON body with yeptris" do
    connection = Faraday.new do |conn|
      conn.adapter :test do |stub|
        stub.get("/specifications/webrtc") do
          [200, { "Content-Type" => "application/hal+json;version=1.0" },
           '{"shortname":"webrtc"}']
        end
      end
    end

    response = connection.get("/specifications/webrtc")
    client.send(:parse_json_body, response)
    expect(response.body).to eq("shortname" => "webrtc")
  end
end
