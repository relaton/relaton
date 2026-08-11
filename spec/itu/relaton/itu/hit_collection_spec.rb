require "relaton/itu/hit_collection"

RSpec.describe Relaton::Itu::HitCollection do
  def row(id, file)
    { id: ::Pubid::Itu.parse(id), file: file }
  end

  def stub_index(rows)
    index = double("Index", search: rows)
    allow(Relaton::Index).to receive(:find_or_create).and_return(index)
    index
  end

  describe "#search" do
    context "error handling" do
      let(:ref) { Relaton::Itu::Pubid.parse("ITU-R BO.600-1") }
      subject(:collection) { described_class.new ref }

      before { stub_index [row("ITU-R BO.600-1", "data/r.yaml")] }

      it "raises RequestError on SocketError" do
        allow_any_instance_of(Mechanize).to receive(:get).and_raise SocketError
        expect { collection.search }.to raise_error Relaton::RequestError, /Could not access/
      end

      it "raises RequestError on Timeout::Error" do
        allow_any_instance_of(Mechanize).to receive(:get).and_raise Timeout::Error
        expect { collection.search }.to raise_error Relaton::RequestError, /Could not access/
      end
    end

    context "with ITU-T ref found in the index" do
      subject(:collection) { described_class.new Relaton::Itu::Pubid.parse("ITU-T Z.100") }

      before do
        stub_index [
          row("ITU-T Z.100 (10/2019)", "data/itu-t-z-100-10-2019.yaml"),
          row("ITU-T Z.100 (06/2021)", "data/itu-t-z-100-06-2021.yaml"),
          row("ITU-T Z.100 (04/2016)", "data/itu-t-z-100-04-2016.yaml"),
        ]
      end

      it "builds one hit per edition, newest first" do
        expect { collection.search }.to output(/Fetching from Relaton repository/).to_stderr_from_any_process
        expect(collection.size).to eq 3
        expect(collection.map { |h| h.hit[:code] }).to eq [
          "ITU-T Z.100 (06/2021)", "ITU-T Z.100 (10/2019)", "ITU-T Z.100 (04/2016)"
        ]
        expect(collection.first.hit[:url]).to eq(
          "#{described_class::GH_ITU}data/itu-t-z-100-06-2021.yaml",
        )
        expect(collection.first.hit[:file]).to eq "data/itu-t-z-100-06-2021.yaml"
      end

      it "does not fetch any document while searching" do
        expect_any_instance_of(Mechanize).not_to receive(:get)
        expect { collection.search }.to output(/Fetching/).to_stderr_from_any_process
      end
    end

    context "with ITU-T ref the index cannot serve" do
      let(:rec_page) do
        double("Page", body: %(<a href="http://handle.itu.int/11.1002/1000/14659-en">H.264</a>))
      end
      let(:editions) do
        double("Response", body: [
          { "idrec" => 14_659, "rec_name" => "H.264 (V14) (08/2021)", "title" => "Advanced video coding" },
          { "idrec" => 12_000, "rec_name" => "H.264 (04/2013)", "title" => "Advanced video coding" },
        ].to_json)
      end

      before do
        allow_any_instance_of(Mechanize).to receive(:get)
          .with(a_string_including("rec.aspx?rec=H.264")).and_return(rec_page)
        allow_any_instance_of(Mechanize).to receive(:get)
          .with(a_string_including("getRecEditions?idrec=14659")).and_return(editions)
      end

      it "falls back to the live path when the index has no row at all" do
        stub_index []
        collection = described_class.new Relaton::Itu::Pubid.parse("ITU-T H.264")

        expect { collection.search }.to output(/Fetching from www\.itu\.int/).to_stderr_from_any_process
        expect(collection.size).to eq 2
        expect(collection.first.hit[:code]).to eq "ITU-T H.264 (V14) (08/2021)"
        expect(collection.first.hit[:url]).to eq "http://handle.itu.int/11.1002/1000/14659-en"
        expect(collection.first.hit[:type]).to eq "recommendation"
        # `ref` would flip Hit#gi_imp onto the Implementers' Guide endpoints
        expect(collection.first.hit).not_to have_key(:ref)
      end

      it "falls back to the live path when no indexed edition has the requested year" do
        stub_index [row("ITU-T H.264 (04/2013)", "data/itu-t-h-264-04-2013.yaml")]
        collection = described_class.new Relaton::Itu::Pubid.parse("ITU-T H.264 (08/2021)")

        expect { collection.search }.to output(/Fetching from www\.itu\.int/).to_stderr_from_any_process
        expect(collection.map { |h| h.hit[:code] }).to include "ITU-T H.264 (V14) (08/2021)"
      end

      it "keeps the indexed editions when the live path finds nothing" do
        stub_index [row("ITU-T H.264 (04/2013)", "data/itu-t-h-264-04-2013.yaml")]
        allow_any_instance_of(Mechanize).to receive(:get)
          .with(a_string_including("rec.aspx")).and_return(double("Page", body: "<html>no match</html>"))
        collection = described_class.new Relaton::Itu::Pubid.parse("ITU-T H.264 (08/2021)")

        expect { collection.search }.to output(/Fetching/).to_stderr_from_any_process
        expect(collection.map { |h| h.hit[:code] }).to eq ["ITU-T H.264 (04/2013)"]
      end

      it "uses the live path for a reference pubid cannot parse" do
        expect(Relaton::Index).not_to receive(:find_or_create)
        allow_any_instance_of(Mechanize).to receive(:get)
          .with(a_string_including("rec.aspx")).and_return(double("Page", body: "<html>no match</html>"))
        collection = described_class.new Relaton::Itu::Pubid.parse("ITU-T G.Suppl.47")

        expect { collection.search }.to output(/Fetching from www\.itu\.int/).to_stderr_from_any_process
        expect(collection).to be_empty
      end

      it "returns empty when rec.aspx responds 404" do
        stub_index []
        page = double("Page", code: "404", uri: URI("https://www.itu.int/x"))
        allow_any_instance_of(Mechanize).to receive(:get)
          .and_raise(Mechanize::ResponseCodeError.new(page))
        collection = described_class.new Relaton::Itu::Pubid.parse("ITU-T Z.9999")

        expect { collection.search }.to output(/Fetching/).to_stderr_from_any_process
        expect(collection).to be_empty
      end
    end

    context "with a publication reference (RR / Operational Bulletin)" do
      it "builds a hit for the Radio Regulations /pub landing page" do
        page = double("Page", uri: URI("https://www.itu.int/pub/R-REG-RR-2020"))
        allow_any_instance_of(Mechanize).to receive(:get).and_return(page)
        collection = described_class.new Relaton::Itu::Pubid.parse("ITU-R RR (2020)")

        expect { collection.search }.to output(/Fetching from www\.itu\.int/).to_stderr_from_any_process
        expect(collection.size).to eq 1
        expect(collection.first.hit[:url]).to eq "https://www.itu.int/pub/R-REG-RR-2020"
        expect(collection.first.hit[:code]).to eq "ITU-R RR (2020)"
        expect(collection.first.hit[:type]).to eq "publication"
      end

      it "builds a hit for the Operational Bulletin /pub landing page" do
        page = double("Page", uri: URI("https://www.itu.int/pub/T-SP-OB.1096-2016"))
        allow_any_instance_of(Mechanize).to receive(:get).and_return(page)
        collection = described_class.new Relaton::Itu::Pubid.parse("ITU-T OB.1096 - 15.III.2016")

        expect { collection.search }.to output(/Fetching/).to_stderr_from_any_process
        expect(collection.first.hit[:url]).to eq "https://www.itu.int/pub/T-SP-OB.1096-2016"
        expect(collection.first.hit[:code]).to eq "ITU-T OB.1096 (2016)"
      end

      it "returns empty when the /pub page redirects to notfound" do
        page = double("Page", uri: URI("https://www.itu.int/en/publications/pages/notfound.aspx"))
        allow_any_instance_of(Mechanize).to receive(:get).and_return(page)
        collection = described_class.new Relaton::Itu::Pubid.parse("ITU-R RR (2014)")

        expect { collection.search }.to output(/Fetching/).to_stderr_from_any_process
        expect(collection).to be_empty
      end

      it "returns empty when the /pub page responds 404" do
        page = double("Page", code: "404", uri: URI("https://www.itu.int/pub/x"))
        allow_any_instance_of(Mechanize).to receive(:get)
          .and_raise(Mechanize::ResponseCodeError.new(page))
        collection = described_class.new Relaton::Itu::Pubid.parse("ITU-R RR (2014)")

        expect { collection.search }.to output(/Fetching/).to_stderr_from_any_process
        expect(collection).to be_empty
      end

      it "returns empty when the bulletin reference carries no number" do
        expect_any_instance_of(Mechanize).not_to receive(:get)
        collection = described_class.new Relaton::Itu::Pubid.parse("ITU-T OB. (2016)")

        expect { collection.search }.to output(/Fetching/).to_stderr_from_any_process
        expect(collection).to be_empty
      end

      it "returns empty when the reference has no year" do
        expect_any_instance_of(Mechanize).not_to receive(:get)
        collection = described_class.new Relaton::Itu::Pubid.parse("ITU-R RR")

        expect { collection.search }.to output(/Fetching/).to_stderr_from_any_process
        expect(collection).to be_empty
      end
    end

    context "with ITU-R ref (request_document path)" do
      let(:ref) { Relaton::Itu::Pubid.parse("ITU-R BO.600-1") }
      subject(:collection) { described_class.new ref }

      it "fetches document from index" do
        stub_index [row("ITU-R BO.600-1", "data/r.yaml")]
        item = double("Item", fetched: nil, "fetched=": nil)
        resp = double("Response", code: "200", body: "---\ntitle: test")
        allow_any_instance_of(Mechanize).to receive(:get).and_return(resp)
        allow(Relaton::Itu::Item).to receive(:from_yaml).and_return(item)

        expect { collection.search }.to output(/Fetching from Relaton repository/).to_stderr_from_any_process
        expect(collection.size).to eq 1
        expect(collection.first.hit[:url]).to eq "#{described_class::GH_ITU}data/r.yaml"
      end

      it "returns empty when index has no match" do
        stub_index []

        expect { collection.search }.to output(/Fetching from Relaton repository/).to_stderr_from_any_process
        expect(collection).to be_empty
      end

      it "returns empty when response is 404" do
        stub_index [row("ITU-R BO.600-1", "data/r.yaml")]
        resp = double("Response", code: "404")
        allow_any_instance_of(Mechanize).to receive(:get).and_return(resp)

        expect { collection.search }.to output(/Fetching from Relaton repository/).to_stderr_from_any_process
        expect(collection).to be_empty
      end

      it "selects the latest version when multiple exist" do
        stub_index [
          row("ITU-R P.838-3", "data/itu-r-p-838-3.yaml"),
          row("ITU-R P.838-2", "data/itu-r-p-838-2.yaml"),
          row("ITU-R P.838-1", "data/itu-r-p-838-1.yaml"),
          row("ITU-R P.838-0", "data/itu-r-p-838-0.yaml"),
        ]
        item = double("Item", fetched: nil, "fetched=": nil)
        resp = double("Response", code: "200", body: "---\ntitle: test")
        allow_any_instance_of(Mechanize).to receive(:get).and_return(resp)
        allow(Relaton::Itu::Item).to receive(:from_yaml).and_return(item)

        col = described_class.new(Relaton::Itu::Pubid.parse("ITU-R P.838"))
        expect { col.search }.to output(/Fetching from Relaton repository/).to_stderr_from_any_process
        expect(col.size).to eq 1
        expect(col.first.hit[:url]).to include("itu-r-p-838-3.yaml")
      end

      it "picks the latest revision when revisions reach double digits" do
        # A lexical string compare would rank "-9" above "-19"; select by number.
        stub_index [
          row("ITU-R P.530-9", "data/itu-r-p-530-9.yaml"),
          row("ITU-R P.530-19", "data/itu-r-p-530-19.yaml"),
          row("ITU-R P.530-18", "data/itu-r-p-530-18.yaml"),
        ]
        item = double("Item", fetched: nil, "fetched=": nil)
        resp = double("Response", code: "200", body: "---\ntitle: test")
        allow_any_instance_of(Mechanize).to receive(:get).and_return(resp)
        allow(Relaton::Itu::Item).to receive(:from_yaml).and_return(item)

        col = described_class.new(Relaton::Itu::Pubid.parse("ITU-R P.530"))
        expect { col.search }.to output(/Fetching from Relaton repository/).to_stderr_from_any_process
        expect(col.first.hit[:url]).to include("itu-r-p-530-19.yaml")
      end
    end
  end

  describe "#index_match?" do
    subject(:collection) { described_class.new(Relaton::Itu::Pubid.parse("ITU-R P.838")) }

    # Both the reference and the index row are Pubid::Itu identifiers — pubid's
    # `matches?` compares structured ids, so the row (deserialized index) is a
    # pubid object, not a string.
    def match?(ref, id)
      collection.send(:index_match?, ::Pubid::Itu.parse(ref), ::Pubid::Itu.parse(id))
    end

    context "part-less reference matches every edition of that exact document" do
      it { expect(match?("ITU-R P.838", "ITU-R P.838")).to be true }
      it { expect(match?("ITU-R P.838", "ITU-R P.838-0")).to be true }
      it { expect(match?("ITU-R P.838", "ITU-R P.838-3")).to be true }
    end

    context "does not over-match a different document number" do
      # a plain substring `include?` would wrongly match all of these
      it { expect(match?("ITU-R M.1", "ITU-R M.10")).to be false }
      it { expect(match?("ITU-R M.1", "ITU-R M.100")).to be false }
      it { expect(match?("ITU-R P.838", "ITU-R P.8380")).to be false }
      it { expect(match?("ITU-R M.1", "ITU-R M.1-1")).to be true }
    end

    context "a reference that names a part matches only that edition" do
      it { expect(match?("ITU-R P.838-2", "ITU-R P.838-2")).to be true }
      it { expect(match?("ITU-R P.838-2", "ITU-R P.838-3")).to be false }
      it { expect(match?("ITU-R P.838-1", "ITU-R P.838-10")).to be false }
    end

    context "an undated ITU-T reference matches every dated edition" do
      it { expect(match?("ITU-T Z.100", "ITU-T Z.100 (06/2021)")).to be true }
      it { expect(match?("ITU-T L.163", "ITU-T L.163 (11/2018)")).to be true }
      it { expect(match?("ITU-T G.780/Y.1351", "ITU-T G.780/Y.1351 (07/2010)")).to be true }
      it { expect(match?("ITU-T G.989.2 Amd 1", "ITU-T G.989.2 (2014) Amd 1 (04/2016)")).to be true }
    end

    context "does not over-match a neighbouring ITU-T document" do
      it { expect(match?("ITU-T L.163", "ITU-T L.1630 (01/2023)")).to be false }
      it { expect(match?("ITU-T H.264", "ITU-T H.264.1 (03/2005)")).to be false }
      it { expect(match?("ITU-T G.989.2", "ITU-T G.989.3 (10/2015)")).to be false }
      it { expect(match?("ITU-T G.780/Y.1351", "ITU-T G.780 (11/1994)")).to be false }
      it { expect(match?("ITU-T G.989.2 Amd 1", "ITU-T G.989.2 (12/2014)")).to be false }
    end

    context "supplements of different series are different documents" do
      # `Supplement#==` compares the series only since pubid #320; before it,
      # a search for `ITU-T A Suppl. 2` matched every series' `Suppl. 2` (42
      # rows across the combined index).
      it { expect(match?("ITU-T A Suppl. 2", "ITU-T A Suppl. 2 (12/2022)")).to be true }
      it { expect(match?("ITU-T A Suppl. 2", "ITU-T D Suppl. 2 (10/1984)")).to be false }
      it { expect(match?("ITU-T A Suppl. 2", "ITU-T G Suppl. 2 (12/1972)")).to be false }
      it { expect(match?("ITU-T A Suppl. 2", "ITU-T A.2 (10/2000)")).to be false }
    end

    context "a version-less reference matches every version" do
      # `(V##)` is a separable trailing component like the date, so the index
      # lookup ignores it and Bibliography narrows afterwards
      it { expect(match?("ITU-T H.264", "ITU-T H.264 (V14) (08/2021)")).to be true }
      it { expect(match?("ITU-T H.264 (V14)", "ITU-T H.264 (05/2003)")).to be true }
      it { expect(match?("ITU-T H.264 (V14)", "ITU-T H.264.1 (03/2005)")).to be false }
    end
  end

  describe "#fetch_item" do
    subject(:collection) { described_class.new(Relaton::Itu::Pubid.parse("ITU-T L.163")) }

    it "returns nil when the document is not in the data repository" do
      # Mechanize raises on 404 instead of returning the response
      page = double("Page", code: "404", uri: URI("https://example.com/x"))
      allow_any_instance_of(Mechanize).to receive(:get)
        .and_raise(Mechanize::ResponseCodeError.new(page))
      expect(collection.fetch_item("#{described_class::GH_ITU}data/x.yaml")).to be_nil
    end

    it "raises RequestError on any other response code" do
      page = double("Page", code: "500", uri: URI("https://example.com/x"))
      allow_any_instance_of(Mechanize).to receive(:get)
        .and_raise(Mechanize::ResponseCodeError.new(page))
      expect { collection.fetch_item("#{described_class::GH_ITU}data/x.yaml") }
        .to raise_error Relaton::RequestError, /Could not access/
    end

    it "raises RequestError when the data repository is unreachable" do
      # a lazily loaded hit is fetched outside #search's rescue
      allow_any_instance_of(Mechanize).to receive(:get).and_raise SocketError
      expect { collection.fetch_item("#{described_class::GH_ITU}data/x.yaml") }
        .to raise_error Relaton::RequestError, /Could not access/
    end

    it "stamps the fetched date on the parsed item" do
      resp = double("Response", code: "200", body: "---\ntitle: test")
      allow_any_instance_of(Mechanize).to receive(:get).and_return(resp)
      item = double("Item")
      expect(item).to receive(:fetched=).with(Date.today.to_s)
      allow(Relaton::Itu::Item).to receive(:from_yaml).and_return(item)

      expect(collection.fetch_item("#{described_class::GH_ITU}data/x.yaml")).to eq item
    end
  end
end
