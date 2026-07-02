# frozen_string_literal: true

RSpec.describe Relaton::Itu::Bibliography do
  let(:pubid) { Relaton::Itu::Pubid.parse("ITU-T A.1") }
  let(:hit_collection) { Relaton::Itu::HitCollection.new(pubid) }

  before do
    allow(Relaton::Itu::HitCollection).to receive(:new).and_return(hit_collection)
    allow(hit_collection).to receive(:search).and_return(hit_collection)
  end

  describe ".search" do
    it "creates HitCollection and calls search" do
      result = described_class.search(pubid)
      expect(Relaton::Itu::HitCollection).to have_received(:new).with(pubid)
      expect(hit_collection).to have_received(:search)
      expect(result).to eq hit_collection
    end

    it "parses String to Pubid first" do
      allow(Relaton::Itu::Pubid).to receive(:parse).and_call_original
      described_class.search("ITU-T A.1")
      expect(Relaton::Itu::Pubid).to have_received(:parse).with("ITU-T A.1")
    end

    it "logs correction hint for malformed string ref" do
      malformed = "ITU-T A.Suppl. 2"
      allow(Relaton::Itu::HitCollection).to receive(:new).and_return(hit_collection)
      expect { described_class.search(malformed) }
        .to output(/Incorrect reference.*the reference should be/).to_stderr_from_any_process
    end

    it "propagates RequestError from HitCollection#search" do
      allow(hit_collection).to receive(:search)
        .and_raise(Relaton::RequestError, "Could not access ITU-T A.1: connection refused")
      expect { described_class.search(pubid) }
        .to raise_error(Relaton::RequestError, /Could not access/)
    end
  end

  describe ".get" do
    let(:docid) { double("Docid", content: "ITU-T A.1") }
    let(:item) do
      double("Item", docidentifier: [docid],
                      to_most_recent_reference: nil,
                      to_all_parts: nil)
    end

    before do
      allow(hit_collection).to receive(:select).and_return([])
    end

    context "when matching result found" do
      let(:hit) { double("Hit", hit: { code: "ITU-T A.1 (2024)" }) }

      before do
        allow(hit_collection).to receive(:select).and_return([hit])
        allow(hit).to receive(:item).and_return(item)
      end

      it "returns item and logs Found" do
        expect { result = described_class.get("ITU-T A.1", "2024") }
          .to output(/Found/).to_stderr_from_any_process
      end

      it "returns the item" do
        result = nil
        expect { result = described_class.get("ITU-T A.1", "2024") }
          .to output.to_stderr_from_any_process
        expect(result).to eq item
      end
    end

    context "when no results" do
      it "returns nil and logs Not found" do
        result = nil
        expect { result = described_class.get("ITU-T A.1", "2024") }
          .to output(/Not found/).to_stderr_from_any_process
        expect(result).to be_nil
      end
    end

    context "with :keep_year option" do
      let(:hit) { double("Hit", hit: { code: "ITU-T A.1 (2024)" }) }

      before do
        allow(hit_collection).to receive(:select).and_return([hit])
        allow(hit).to receive(:item).and_return(item)
      end

      it "skips to_most_recent_reference" do
        expect { described_class.get("ITU-T A.1", "2024", keep_year: true) }
          .to output.to_stderr_from_any_process
        expect(item).not_to have_received(:to_most_recent_reference)
      end
    end

    context "without year and without :keep_year" do
      let(:hit) { double("Hit", hit: { code: "ITU-T A.1" }) }
      let(:recent_item) { double("RecentItem") }

      before do
        allow(hit_collection).to receive(:select).and_return([hit])
        allow(hit).to receive(:item).and_return(item)
        allow(item).to receive(:to_most_recent_reference).and_return(recent_item)
      end

      it "calls to_most_recent_reference" do
        expect { described_class.get("ITU-T A.1") }
          .to output.to_stderr_from_any_process
        expect(item).to have_received(:to_most_recent_reference)
      end
    end

    context "with :all_parts option" do
      let(:hit) { double("Hit", hit: { code: "ITU-T A.1 (2024)" }) }
      let(:all_parts_item) { double("AllPartsItem") }

      before do
        allow(hit_collection).to receive(:select).and_return([hit])
        allow(hit).to receive(:item).and_return(item)
        allow(item).to receive(:to_all_parts).and_return(all_parts_item)
      end

      it "calls to_all_parts" do
        result = nil
        expect { result = described_class.get("ITU-T A.1", "2024", all_parts: true) }
          .to output.to_stderr_from_any_process
        expect(item).to have_received(:to_all_parts)
        expect(result).to eq all_parts_item
      end
    end
  end

  describe "private methods" do
    describe "#fetch_ref_err" do
      let(:refid) { Relaton::Itu::Pubid.parse("ITU-T A.1 (2020)") }

      it "logs Not found" do
        expect { described_class.send(:fetch_ref_err, refid, []) }
          .to output(/Not found/).to_stderr_from_any_process
      end

      it "logs year mismatch info when missed_years present" do
        expect { described_class.send(:fetch_ref_err, refid, ["2019"]) }
          .to output(/no match for `2020` year.*matches found for `2019`/m).to_stderr_from_any_process
      end

      it "returns nil" do
        result = nil
        expect { result = described_class.send(:fetch_ref_err, refid, []) }
          .to output.to_stderr_from_any_process
        expect(result).to be_nil
      end
    end

    describe "#isobib_results_filter" do
      let(:item) { double("Item") }

      it "returns {ret: item} when year matches" do
        refid = Relaton::Itu::Pubid.parse("ITU-T A.1 (2019)")
        hit = double("Hit", hit: { code: "ITU-T A.1 (2019)" })
        allow(hit).to receive(:item).and_return(item)

        result = described_class.send(:isobib_results_filter, [hit], refid)
        expect(result).to eq({ ret: item })
      end

      it "returns {years: [...]} when year does not match" do
        refid = Relaton::Itu::Pubid.parse("ITU-T A.1 (2020)")
        hit = double("Hit", hit: { code: "ITU-T A.1 (2019)" })

        result = described_class.send(:isobib_results_filter, [hit], refid)
        expect(result).to eq({ years: ["2019"] })
      end

      it "returns {ret: item} when refid has no year" do
        refid = Relaton::Itu::Pubid.parse("ITU-T A.1")
        hit = double("Hit", hit: { code: "ITU-T A.1 (2019)" })
        allow(hit).to receive(:item).and_return(item)

        result = described_class.send(:isobib_results_filter, [hit], refid)
        expect(result).to eq({ ret: item })
      end
    end
  end
end
