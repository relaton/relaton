require "relaton/itu/hit_collection"

RSpec.describe Relaton::Itu::HitCollection do
  describe "#search" do
    context "error handling" do
      let(:ref) { Relaton::Itu::Pubid.parse("ITU-R BO.600-1") }
      subject(:collection) { described_class.new ref }

      before do
        index = double("Index", search: [{ id: "ITU-R BO.600-1", file: "data/r.yaml" }])
        allow(Relaton::Index).to receive(:find_or_create).and_return(index)
      end

      it "raises RequestError on SocketError" do
        allow_any_instance_of(Mechanize).to receive(:get).and_raise SocketError
        expect { collection.search }.to raise_error Relaton::RequestError, /Could not access/
      end

      it "raises RequestError on Timeout::Error" do
        allow_any_instance_of(Mechanize).to receive(:get).and_raise Timeout::Error
        expect { collection.search }.to raise_error Relaton::RequestError, /Could not access/
      end
    end

    context "with ITU-T ref (request_search path)" do
      let(:ref) { Relaton::Itu::Pubid.parse("ITU-T T.4") }
      subject(:collection) { described_class.new ref }

      let(:search_response_body) do
        { "results" => [
          { "Media" => { "Name" => "ITU-T T.4" },
            "Title" => "Standardization of Group 3 facsimile terminals",
            "Redirection" => "/rec/T-REC-T.4",
            "Collection" => { "Group" => "Recommendations" } },
        ] }.to_json
      end

      it "posts to search API and populates hits" do
        resp = double("Response", body: search_response_body)
        allow_any_instance_of(Mechanize).to receive(:post).and_return(resp)

        expect { collection.search }.to output(/Fetching from www\.itu\.int/).to_stderr_from_any_process
        expect(collection.size).to eq 1
        expect(collection.first.hit[:code]).to eq "ITU-T T.4"
      end
    end

    context "with ITU-R ref (request_document path)" do
      let(:ref) { Relaton::Itu::Pubid.parse("ITU-R BO.600-1") }
      subject(:collection) { described_class.new ref }

      it "fetches document from index" do
        index = double("Index", search: [{ id: "ITU-R BO.600-1", file: "data/r.yaml" }])
        allow(Relaton::Index).to receive(:find_or_create).and_return(index)
        item = double("Item", fetched: nil, "fetched=": nil)
        resp = double("Response", code: "200", body: "---\ntitle: test")
        allow_any_instance_of(Mechanize).to receive(:get).and_return(resp)
        allow(Relaton::Itu::Item).to receive(:from_yaml).and_return(item)

        expect { collection.search }.to output(/Fetching from Relaton repository/).to_stderr_from_any_process
        expect(collection.size).to eq 1
      end

      it "returns empty when index has no match" do
        index = double("Index", search: [])
        allow(Relaton::Index).to receive(:find_or_create).and_return(index)

        expect { collection.search }.to output(/Fetching from Relaton repository/).to_stderr_from_any_process
        expect(collection).to be_empty
      end

      it "returns empty when response is 404" do
        index = double("Index", search: [{ id: "ITU-R BO.600-1", file: "data/r.yaml" }])
        allow(Relaton::Index).to receive(:find_or_create).and_return(index)
        resp = double("Response", code: "404")
        allow_any_instance_of(Mechanize).to receive(:get).and_return(resp)

        expect { collection.search }.to output(/Fetching from Relaton repository/).to_stderr_from_any_process
        expect(collection).to be_empty
      end

      it "selects the latest version when multiple exist" do
        index = double("Index", search: [
          { id: "ITU-R P.838-3", file: "data/itu-r-p-838-3.yaml" },
          { id: "ITU-R P.838-2", file: "data/itu-r-p-838-2.yaml" },
          { id: "ITU-R P.838-1", file: "data/itu-r-p-838-1.yaml" },
          { id: "ITU-R P.838-0", file: "data/itu-r-p-838-0.yaml" },
        ])
        allow(Relaton::Index).to receive(:find_or_create).and_return(index)
        item = double("Item", fetched: nil, "fetched=": nil)
        resp = double("Response", code: "200", body: "---\ntitle: test")
        allow_any_instance_of(Mechanize).to receive(:get).and_return(resp)
        allow(Relaton::Itu::Item).to receive(:from_yaml).and_return(item)

        ref = Relaton::Itu::Pubid.parse("ITU-R P.838")
        col = described_class.new(ref)
        expect { col.search }.to output(/Fetching from Relaton repository/).to_stderr_from_any_process
        expect(col.size).to eq 1
        expect(col.first.hit[:url]).to include("itu-r-p-838-3.yaml")
      end
    end
  end
end
