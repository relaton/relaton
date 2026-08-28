require "relaton/iala"

RSpec.describe Relaton::Iala::Bibliography do
  # Every example searches the offline `index-v2` fixture seeded by
  # spec/iala/support/webmock.rb — a curated subset of the published index.
  def match(ref)
    described_class.send(:best_match, ref)&.fetch(:file)
  end

  context "index narrowing" do
    let(:index) { described_class.send(:index) }

    it "deserializes the rows into pubid identifiers" do
      expect(index.index).to all(include(id: an_instance_of(Pubid::Iala::Identifiers::Manual))
        .or(include(id: an_instance_of(Pubid::Iala::Identifiers::Recommendation)))
        .or(include(id: an_instance_of(Pubid::Iala::Identifiers::ModelCourse)))
        .or(include(id: an_instance_of(Pubid::Iala::Identifiers::Standard))))
    end

    it "binary-searches by number instead of scanning the whole index" do
      pubid = Pubid::Iala::Identifier.parse "IALA R0106"
      candidates = index.send(:candidates_by_number, pubid)
      expect(index.index.size).to eq 19
      expect(candidates.size).to eq 4
      expect(candidates.map { |r| r[:id].number }.uniq).to eq ["0106"]
    end
  end

  context "row selection" do
    it "returns the newest edition" do
      # 0101 is published as edition "2" and edition "3.0".
      expect(match("IALA R0101")).to eq "data/r0101-3.0.yaml"
    end

    it "prefers the language-neutral record over its translations" do
      expect(match("IALA M0001")).to eq "data/m0001-9.0.yaml"
    end

    it "honours a language the reference asks for" do
      expect(match("IALA R0106 Ed 2.1 (F)")).to eq "data/r0106-2.1-f.yaml"
    end

    it "honours an edition the reference asks for" do
      expect(match("IALA R0106 Ed 2.0")).to eq "data/r0106-2.0-s.yaml"
    end

    it "keeps two document types that share a number apart" do
      expect(match("IALA R1001")).to eq "data/r1001-2.0.yaml"
      expect(match("IALA C1001")).to eq "data/c1001-3.1.yaml"
    end

    it "finds a sub-part folded into the number" do
      expect(match("IALA C0103-1")).to eq "data/c0103-1-3.0.yaml"
    end

    it "zero-pads the number to its canonical width" do
      expect(match("IALA M1")).to eq "data/m0001-9.0.yaml"
    end

    it "returns nil for a document not in the index" do
      expect(match("IALA S9999")).to be_nil
    end

    it "falls back to a substring scan when pubid cannot parse the reference" do
      # `Util.warn` reaches the logger through `method_missing`, so the
      # expectation goes on the pool rather than on `Util` (a partial double
      # there would be shadowed by the private `Kernel#warn`).
      expect(Relaton.logger_pool).to receive(:warn)
        .with(/Failed to parse pubid/, any_args)
      # "Ed 2.1" is not an identifier, but it is a substring of the rendered
      # `IALA R0106 Ed 2.1` rows, which is all the fallback scan compares.
      expect(match("Ed 2.1")).to eq "data/r0106-2.1.yaml"
    end

    it "returns nil when an unparseable reference matches nothing" do
      allow(Relaton.logger_pool).to receive(:warn)
      expect(match("not an identifier")).to be_nil
    end
  end

  context "#search" do
    let(:yaml) do
      <<~YAML
        ---
        id: S1070-2.0
        type: standard
        title:
        - language: eng
          content: Information Services
          type: main
        docidentifier:
        - content: IALA S1070 Ed 2.0
          type: IALA
          primary: true
        ext:
          doctype:
            content: standard
          flavor: iala
      YAML
    end

    it "fetches the matched document" do
      stub_request(:get, "#{described_class::ENDPOINT}data/s1070-2.0.yaml")
        .to_return(status: 200, body: yaml)
      item = described_class.search "IALA S1070"
      expect(item).to be_a Relaton::Iala::ItemData
      expect(item.docidentifier.first.content).to eq "IALA S1070 Ed 2.0"
      expect(item.fetched).to eq Date.today.to_s
    end

    it "raises RequestError when the document is unreachable" do
      stub_request(:get, "#{described_class::ENDPOINT}data/s1070-2.0.yaml")
        .to_return(status: 404)
      expect { described_class.search "IALA S1070" }
        .to raise_error Relaton::RequestError, /HTTP 404/
    end

    it "returns nil when nothing matches" do
      expect(described_class.search("IALA S9999")).to be_nil
    end
  end
end
