# frozen_string_literal: true

RSpec.describe Relaton::Itu::Bibliography do
  let(:pubid) { ::Pubid::Itu.parse("ITU-T A.1") }
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

    it "parses a String reference with Pubid::Itu" do
      allow(::Pubid::Itu).to receive(:parse).and_call_original
      described_class.search("ITU-T A.1")
      expect(::Pubid::Itu).to have_received(:parse).with("ITU-T A.1")
    end

    # The reference reaches HitCollection as the identifier the caller wrote:
    # the parse keeps every component, and it keeps the identifier type.
    def searched_with(ref)
      described_class.search(ref)
      pubid = nil
      expect(Relaton::Itu::HitCollection).to have_received(:new) { |arg| pubid = arg }
      pubid
    end

    it "keeps the version and the date of a bare `v10` spelling" do
      expect(searched_with("ITU-T H.222.0 v10 (04/2025)").to_s).to eq "ITU-T H.222.0 (V10) (04/2025)"
    end

    it "reads ITU's publication id as the dated recommendation" do
      expect(searched_with("T-REC-T.4-200307-I").to_s).to eq "ITU-T T.4 (07/2003)"
    end

    it "drops the redundant REC type word" do
      expect(searched_with("ITU-T REC T.4").to_s).to eq "ITU-T T.4"
    end

    it "reads a -YYYYMM suffix as the edition date, not as a part" do
      expect(searched_with("ITU-T T.4-200307").to_s).to eq "ITU-T T.4 (07/2003)"
    end

    # ITU-R Recommendations and Reports number independently, so the bare
    # "ITU-R BT.2020-1" names both Rec. BT.2020-1 (06/2014) and Report
    # BT.2020-1 (2000). Both citation orders of the Report must stay a Report.
    it "keeps a Report distinct from the Recommendation of the same number" do
      expect(searched_with("ITU-R Report BT.2020-1")).to be_a ::Pubid::Itu::Identifiers::Report
    end

    it "parses the Radio Regulations and the Operational Bulletins" do
      expect(searched_with("ITU-R RR (2020)")).to be_a ::Pubid::Itu::Identifiers::RadioRegulations
    end

    it "logs correction hint for malformed string ref" do
      malformed = "ITU-T A.Suppl. 2"
      expect do
        expect { described_class.search(malformed) }.to raise_error ::Pubid::Errors::ParseError
      end.to output(/Incorrect reference.*the reference should be/).to_stderr_from_any_process
    end

    # relaton-cli rescues Pubid::Errors::Error and prints "not a recognized
    # standards identifier". Returning nil would make "malformed" look like
    # "not found".
    it "raises a Pubid parse error for a reference Pubid::Itu cannot parse" do
      expect { described_class.search("ITU G.191") }.to raise_error(::Pubid::Errors::ParseError) { |e|
        expect(e).to be_a ::Pubid::Errors::Error
      }
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

    it "adds the year argument to a reference that carries none" do
      expect { described_class.get("ITU-R RR", "2020") }.to output.to_stderr_from_any_process
      expect(Relaton::Itu::HitCollection).to have_received(:new) { |ref|
        expect(ref).to be_a ::Pubid::Itu::Identifiers::RadioRegulations
        expect(ref.to_s).to eq "ITU-R RR (2020)"
      }
    end

    it "adds the year argument to a parsed pubid, and leaves it as it was (relaton#205)" do
      ref = ::Pubid::Itu.parse "ITU-R RR"
      hash = ref.to_hash
      expect { described_class.get(ref, "2020") }.to output.to_stderr_from_any_process
      expect(Relaton::Itu::HitCollection).to have_received(:new) { |refid|
        expect(refid.to_s).to eq "ITU-R RR (2020)"
      }
      expect(ref.to_hash).to eq hash
    end

    it "keeps the year the reference already names" do
      expect { described_class.get("ITU-T A.1 (2019)", "2024") }.to output.to_stderr_from_any_process
      expect(Relaton::Itu::HitCollection).to have_received(:new) { |ref| expect(ref.to_s).to eq "ITU-T A.1 (2019)" }
    end

    it "raises a Pubid parse error for a reference Pubid::Itu cannot parse" do
      expect { described_class.get("ITU-T G.Suppl.47") }
        .to raise_error(::Pubid::Errors::ParseError)
        .and output(/Incorrect reference/).to_stderr_from_any_process
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
      let(:refid) { ::Pubid::Itu.parse("ITU-T A.1 (2020)") }

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

    describe "#search_filter" do
      def filtered(ref, *codes)
        hits = codes.map { |c| double("Hit", hit: { code: c }) }
        allow(described_class).to receive(:search).and_return(hits)
        described_class.send(:search_filter, ::Pubid::Itu.parse(ref)).map { |h| h.hit[:code] }
      end

      it "keeps every dated edition of the referenced document" do
        expect(filtered("ITU-T A.1 (2019)", "ITU-T A.1 (10/2000)", "ITU-T A.1 (2019)"))
          .to eq ["ITU-T A.1 (10/2000)", "ITU-T A.1 (2019)"]
      end

      it "drops a supplement of the referenced document" do
        expect(filtered("ITU-T G.989.2", "ITU-T G.989.2 (12/2014)", "ITU-T G.989.2 (2014) Amd. 1 (04/2016)"))
          .to eq ["ITU-T G.989.2 (12/2014)"]
      end

      # The old local grammar did not model `Cor.`/`Err.`: it stopped at the
      # base's date, so a base reference kept its own corrigenda and errata.
      it "drops a corrigendum and an erratum of the referenced document" do
        expect(filtered("ITU-T Z.100", "ITU-T Z.100 (06/2021)", "ITU-T Z.100 (1999) Cor. 1 (10/2001)"))
          .to eq ["ITU-T Z.100 (06/2021)"]
        expect(filtered("ITU-T A.13", "ITU-T A.13 (2019)", "ITU-T A.13 (2019) Err. 1 (02/2023)"))
          .to eq ["ITU-T A.13 (2019)"]
      end

      # Both are "Amd. 1" of G.989.2, to different editions. A reference that
      # dates the amendment itself names one of them.
      it "narrows to the amendment the reference dates" do
        expect(filtered("ITU-T G.989.2 Amd. 1 (04/2016)",
                        "ITU-T G.989.2 (2019) Amd. 1 (10/2020)", "ITU-T G.989.2 (2014) Amd. 1 (04/2016)"))
          .to eq ["ITU-T G.989.2 (2014) Amd. 1 (04/2016)"]
      end

      it "narrows to the version the amended recommendation names" do
        expect(filtered("ITU-T H.264 (V14) (2019) Amd. 1",
                        "ITU-T H.264 (V14) (2019) Amd. 1 (01/2020)", "ITU-T H.264 (V13) (2019) Amd. 1 (01/2020)"))
          .to eq ["ITU-T H.264 (V14) (2019) Amd. 1 (01/2020)"]
      end

      it "does not keep a document with a longer number" do
        expect(filtered("ITU-T H.264", "ITU-T H.264 (05/2003)", "ITU-T H.264.1 (03/2005)"))
          .to eq ["ITU-T H.264 (05/2003)"]
      end

      it "narrows to the version the reference names" do
        expect(filtered("ITU-T H.264 (V14)", "ITU-T H.264 (V14) (08/2021)", "ITU-T H.264 (05/2003)"))
          .to eq ["ITU-T H.264 (V14) (08/2021)"]
      end

      it "keeps every version when the reference names none" do
        expect(filtered("ITU-T H.264", "ITU-T H.264 (V14) (08/2021)", "ITU-T H.264 (05/2003)"))
          .to eq ["ITU-T H.264 (V14) (08/2021)", "ITU-T H.264 (05/2003)"]
      end

      it "does not answer a Report with the Recommendation of the same number" do
        expect(filtered("Report ITU-R BT.2020-1", "ITU-R BT.2020-1", "Report ITU-R BT.2020-1"))
          .to eq ["Report ITU-R BT.2020-1"]
      end

      it "keeps a hit that carries no code" do
        hit = double("Hit", hit: { url: "u" })
        allow(described_class).to receive(:search).and_return([hit])
        expect(described_class.send(:search_filter, ::Pubid::Itu.parse("ITU-R BO.600-1"))).to eq [hit]
      end
    end

    # The year a hit is filtered on is the first date of its code — for an
    # amendment, the year of the recommendation it amends. The reference's
    # year must be read the same way.
    describe "#edition_year" do
      def year(ref) = described_class.send(:edition_year, ::Pubid::Itu.parse(ref))

      it { expect(year("ITU-T A.1 (10/2000)")).to eq "2000" }
      it { expect(year("ITU-T A.1")).to be_nil }
      it { expect(year("ITU-T A Suppl. 2 (12/2022)")).to eq "2022" }
      it { expect(year("ITU-T Z.100 Annex F2 (06/2021)")).to eq "2021" }
      it { expect(year("ITU-T Z.100 (06/2021) Annex F1")).to eq "2021" }
      it { expect(year("ITU-T G.989.2 (2014) Amd. 1 (04/2016)")).to eq "2014" }
      it { expect(year("ITU-T G.989.2 Amd. 1 (04/2016)")).to be_nil }
    end

    describe "#isobib_results_filter" do
      let(:item) { double("Item") }

      it "reads an amendment reference's year from the amended recommendation" do
        refid = ::Pubid::Itu.parse("ITU-T G.989.2 Amd. 1 (04/2016)")
        hit = double("Hit", hit: { code: "ITU-T G.989.2 (2014) Amd. 1 (04/2016)" })
        allow(hit).to receive(:item).and_return(item)

        expect(described_class.send(:isobib_results_filter, [hit], refid)).to eq({ ret: item })
      end

      it "returns {ret: item} when year matches" do
        refid = ::Pubid::Itu.parse("ITU-T A.1 (2019)")
        hit = double("Hit", hit: { code: "ITU-T A.1 (2019)" })
        allow(hit).to receive(:item).and_return(item)

        result = described_class.send(:isobib_results_filter, [hit], refid)
        expect(result).to eq({ ret: item })
      end

      it "returns {years: [...]} when year does not match" do
        refid = ::Pubid::Itu.parse("ITU-T A.1 (2020)")
        hit = double("Hit", hit: { code: "ITU-T A.1 (2019)" })

        result = described_class.send(:isobib_results_filter, [hit], refid)
        expect(result).to eq({ years: ["2019"] })
      end

      it "returns {ret: item} when refid has no year" do
        refid = ::Pubid::Itu.parse("ITU-T A.1")
        hit = double("Hit", hit: { code: "ITU-T A.1 (2019)" })
        allow(hit).to receive(:item).and_return(item)

        result = described_class.send(:isobib_results_filter, [hit], refid)
        expect(result).to eq({ ret: item })
      end
    end
  end
end
