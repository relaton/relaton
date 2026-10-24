require "spec_helper"
require "relaton/equivalence"

describe Relaton::Equivalence do
  before { described_class.reset! }
  after { described_class.reset! }

  let(:table) do
    { "chains" => [
        { "match" => '^BS EN (.+)$', "resolve" => ["EN \\1", "\\1"] },
        { "match" => '^EN (.+)$', "resolve" => ["\\1"] },
      ],
      "equivalences" => [
        { "canonical" => "ISO/IEC 17025", "equivalents" => ["EN ISO/IEC 17025"] },
      ] }
  end

  before do
    dir = Dir.mktmpdir
    File.write(File.join(dir, "t.yaml"), YAML.dump(table))
    described_class.register(dir)
  end

  describe ".canonical_for" do
    it "resolves the first chain step" do
      expect(described_class.canonical_for("BS EN 1388")).to eq("EN 1388")
    end

    it "never returns the code itself" do
      expect(described_class.canonical_for("1388")).to be_nil
    end

    it "resolves explicit equivalences" do
      expect(described_class.canonical_for("EN ISO/IEC 17025")).to eq("ISO/IEC 17025")
    end

    it "answers nil for the canonical form" do
      expect(described_class.canonical_for("ISO/IEC 17025")).to be_nil
    end
  end

  describe ".equivalents_for" do
    it "chains to the root, canonical first" do
      expect(described_class.equivalents_for("BS EN 1388")).to eq(["EN 1388", "1388"])
    end

    it "is empty for an unmapped code" do
      expect(described_class.equivalents_for("ISO 1")).to eq([])
    end
  end

  it "ships a seed table with the CEN/BSI/DIN/NF adoption ladder" do
    described_class.reset!
    described_class.load_seed
    expect(described_class.canonical_for("BS EN ISO 1388")).to eq("EN ISO 1388")
    expect(described_class.equivalents_for("BS EN ISO 1388")).to eq(["EN ISO 1388", "ISO 1388"])
  end

  describe ".related_for" do
    let(:table) do
      { "chains" => [
          { "match" => '^BS EN (.+)$', "resolve" => ["EN \\1", "\\1"] },
          { "match" => '^EN (.+)$', "resolve" => ["\\1"] },
        ],
        "equivalences" => [
          { "canonical" => "RFC 7200", "equivalents" => ["IETF RFC 7200"] },
        ],
        "adoptions" => [
          { "pattern" => '^(ISO[ /].+)$', "forms" => ["EN \\1", "BS EN \\1"] },
        ] }
    end

    it "walks down the canonical chain" do
      expect(described_class.related_for("BS EN ISO 1388")).to eq(
        ["EN ISO 1388", "ISO 1388"]
      )
    end

    it "generates the adoption ladder from the base" do
      expect(described_class.related_for("ISO 1388")).to eq(["EN ISO 1388", "BS EN ISO 1388"])
    end

    it "generates the ladder off the walked canonical and excludes the code" do
      expect(described_class.related_for("EN ISO 1388")).to eq(["ISO 1388", "BS EN ISO 1388"])
    end

    it "declares variant spellings as equivalence edges" do
      expect(described_class.related_for("IETF RFC 7200")).to eq(["RFC 7200"])
    end

    it "answers [] for an unmapped code" do
      expect(described_class.related_for("RFC 1")).to eq([])
    end
  end

  it "ships a bidirectional seed ladder" do
    described_class.reset!
    described_class.load_seed
    expect(described_class.related_for("ISO 1388")).to eq(
      ["EN ISO 1388", "BS EN ISO 1388", "DIN EN ISO 1388", "NF EN ISO 1388"]
    )
    expect(described_class.canonical_for("IEC/ISO 14515-1")).to eq("ISO/IEC 14515-1")
    expect(described_class.canonical_for("IETF RFC 7200")).to eq("RFC 7200")
  end
end
