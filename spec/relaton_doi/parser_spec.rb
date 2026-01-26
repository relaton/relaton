# frozen_string_literal: true

RSpec.describe RelatonDoi::Parser do
  describe "#fetch_crossref" do
    let(:parser) { described_class.new({}) }
    let(:query) { "test+query" }
    let(:filter) { "type:book" }
    let(:url) { "https://api.crossref.org/works?query=#{query}&filter=#{filter}" }
    let(:items) { [{ "title" => ["Test"] }] }
    let(:success_body) { { "message" => { "items" => items } }.to_json }

    context "when response is 2xx" do
      it "returns items array" do
        resp = double(status: 200, body: success_body)
        expect(Faraday).to receive(:get).with(url).and_return(resp)
        expect(parser.fetch_crossref(query: query, filter: filter)).to eq items
      end
    end

    context "when response is 4xx" do
      it "returns nil" do
        resp = double(status: 404, body: "Not found")
        expect(Faraday).to receive(:get).with(url).and_return(resp)
        expect(parser.fetch_crossref(query: query, filter: filter)).to be_nil
      end
    end

    context "when response is 5xx" do
      it "raises RequestError" do
        resp = double(status: 500, body: "Internal Server Error")
        expect(Faraday).to receive(:get).with(url).and_return(resp)
        expect do
          parser.fetch_crossref(query: query, filter: filter)
        end.to raise_error(RelatonBib::RequestError, /Crossref request failed: 500/)
      end
    end

    context "when network error occurs" do
      it "retries MAX_RETRIES times then raises RequestError" do
        expect(Faraday).to receive(:get).with(url)
          .exactly(RelatonDoi::Parser::MAX_RETRIES + 1).times
          .and_raise(Faraday::ConnectionFailed.new("Connection refused"))
        expect do
          parser.fetch_crossref(query: query, filter: filter)
        end.to raise_error(RelatonBib::RequestError, /Crossref network error after 3 retries/)
      end

      it "returns result if succeeds after retry" do
        resp = double(status: 200, body: success_body)
        call_count = 0
        allow(Faraday).to receive(:get).with(url) do
          call_count += 1
          raise Faraday::ConnectionFailed, "Connection refused" if call_count < 3
          resp
        end
        expect(parser.fetch_crossref(query: query, filter: filter)).to eq items
      end
    end

    context "when JSON parsing fails" do
      it "raises RequestError" do
        resp = double(status: 200, body: "invalid json")
        expect(Faraday).to receive(:get).with(url).and_return(resp)
        expect do
          parser.fetch_crossref(query: query, filter: filter)
        end.to raise_error(RelatonBib::RequestError, /Crossref JSON parsing error/)
      end
    end
  end
end
