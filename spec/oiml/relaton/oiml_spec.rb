RSpec.describe Relaton::Oiml do
  it "has a version number" do
    expect(Relaton::VERSION).not_to be nil
  end

  it "returns grammar hash" do
    hash = Relaton::Oiml.grammar_hash
    expect(hash).to be_instance_of String
    expect(hash.size).to eq 32
  end

  context "get document", skip: "combined-bundle pubid from_hash regression (tracked)" do
    it "by abstract code (latest edition, no language)" do
      expect do
        result = Relaton::Oiml::Bibliography.get "OIML R 138"
        expect(result).to be_instance_of Relaton::Oiml::ItemData
        expect(result.docidentifier.first.content).to eq "OIML R 138"
      end.to output(
        %r{\[relaton-oiml\] INFO: \(OIML R 138\) Fetching from Relaton repository},
      ).to_stderr_from_any_process
    end

    it "by code with edition and language" do
      result = Relaton::Oiml::Bibliography.get "OIML R 138:2007 (E)"
      expect(result.docidentifier.first.content).to eq "OIML R 138:2007 (E)"
    end

    it "by code and language without an edition year" do
      result = Relaton::Oiml::Bibliography.get "OIML R 138 (E)"
      expect(result.docidentifier.first.content).to eq "OIML R 138 (E)"
    end

    it "exposes OIML-specific ext fields" do
      result = Relaton::Oiml::Bibliography.get "OIML R 138"
      expect(result.ext.scope).to start_with "This Recommendation applies"
      expect(result.ext.quantity).to eq "Volume"
      expect(result.ext.measuring_instrument).to eq "Volumetric container"
      expect(result.ext.focus_area).to eq "Trade"
      expect(result.ext.sustainability_framework).to eq "People"
      expect(result.ext.doi).to eq "10.63493/r138.2007.en"
    end

    it "stamps the fetched date" do
      result = Relaton::Oiml::Bibliography.get "OIML R 138"
      expect(result.fetched).to eq Date.today.to_s
    end

    it "not found" do
      expect do
        expect(Relaton::Oiml::Bibliography.get("OIML R 9999")).to be_nil
      end.to output(
        %r{\[relaton-oiml\] INFO: \(OIML R 9999\) Not found\.},
      ).to_stderr_from_any_process
    end

    it "raises on an unparseable reference" do
      expect { Relaton::Oiml::Bibliography.get "not a reference" }
        .to raise_error(StandardError)
    end
  end

  # These exercise the undated-reference handling (issue #72) without the index,
  # so they run despite the tracked combined-bundle `from_hash` regression that
  # keeps the "get document" context above skipped. `Item.from_yaml` and
  # `Pubid::Oiml.parse` do not use `from_hash`.
  context "undated reference (issue #72)" do
    let(:fixture) { File.read "fixtures/data/r138_2007.yaml" }

    it "strips the edition year via #to_most_recent_reference" do
      item = Relaton::Oiml::Item.from_yaml fixture
      expect(item.docidentifier.first.content).to eq "OIML R 138:2007"

      recent = item.to_most_recent_reference
      expect(recent.docidentifier.first.content).to eq "OIML R 138"
      expect(recent.date).to be_empty
    end

    context "#get" do
      before do
        allow(Relaton::Oiml::Bibliography).to receive(:search) do
          Relaton::Oiml::Item.from_yaml fixture
        end
      end

      it "renders undated for an undated citation" do
        result = Relaton::Oiml::Bibliography.get "OIML R 138"
        expect(result.docidentifier.first.content).to eq "OIML R 138"
      end

      it "pins the edition for a dated citation" do
        result = Relaton::Oiml::Bibliography.get "OIML R 138:2007"
        expect(result.docidentifier.first.content).to eq "OIML R 138:2007"
      end

      it "pins the edition when the year is passed as an argument" do
        result = Relaton::Oiml::Bibliography.get "OIML R 138", "2007"
        expect(result.docidentifier.first.content).to eq "OIML R 138:2007"
      end

      it "retains the year for an undated citation when keep_year is set" do
        result = Relaton::Oiml::Bibliography.get "OIML R 138", nil, keep_year: true
        expect(result.docidentifier.first.content).to eq "OIML R 138:2007"
      end

      it "strips the year for a dated citation when keep_year is false" do
        result = Relaton::Oiml::Bibliography.get "OIML R 138:2007", nil, keep_year: false
        expect(result.docidentifier.first.content).to eq "OIML R 138"
      end
    end

    context "#get with a language suffix" do
      before do
        allow(Relaton::Oiml::Bibliography).to receive(:search) do
          Relaton::Oiml::Item.from_yaml File.read("fixtures/data/r138_2007_eng.yaml")
        end
      end

      it "renders undated while keeping the language for an undated citation" do
        result = Relaton::Oiml::Bibliography.get "OIML R 138 (E)"
        expect(result.docidentifier.first.content).to eq "OIML R 138 (E)"
      end

      it "keeps the year and the language for a dated citation" do
        result = Relaton::Oiml::Bibliography.get "OIML R 138:2007 (E)"
        expect(result.docidentifier.first.content).to eq "OIML R 138:2007 (E)"
      end
    end
  end
end
