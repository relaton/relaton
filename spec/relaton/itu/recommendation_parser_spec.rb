require "relaton/itu/recommendation_parser"

RSpec.describe Relaton::Itu::RecommendationParser do
  let(:agent) { instance_double Mechanize }
  let(:hit_collection) { double("Hit collection", agent: agent) }
  let(:hit) { double("Hit", hit_collection: hit_collection) }
  let(:idrec) { 12345 }
  let(:imp) { false }
  subject(:parser) { described_class.new hit, idrec, imp }

  describe "#doc" do
    it "raises RequestError on SocketError" do
      expect(agent).to receive(:get).and_raise SocketError
      expect { parser.doc }.to raise_error Relaton::RequestError, /Could not access/
    end

    it "raises RequestError on Timeout::Error" do
      expect(agent).to receive(:get).and_raise Timeout::Error
      expect { parser.doc }.to raise_error Relaton::RequestError, /Could not access/
    end
  end
end
