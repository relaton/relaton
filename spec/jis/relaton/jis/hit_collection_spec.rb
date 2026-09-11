# frozen_string_literal: true

# Record selection against the pooled index-v2 fixture. Every example stubs the
# document fetch and checks which data file the flavor asks for, so no example
# touches the network.
describe Relaton::Jis::HitCollection do
  let(:data_url) { "#{described_class::GH_URL}data/" }

  before do
    stub_request(:get, /\A#{Regexp.escape data_url}/)
      .to_return body: File.read("fixtures/item.yaml", encoding: "UTF-8")
  end

  def collection(ref)
    described_class.new Pubid::Jis::Identifier.parse(ref)
  end

  def fetched(file)
    a_request(:get, "#{data_url}#{file}")
  end

  shared_examples "resolves to" do |ref, file|
    it "#{ref} -> #{file}" do
      collection(ref).find
      expect(fetched(file)).to have_been_made.once
    end
  end

  context "a supplement of a part" do
    # The base document's part identifies the supplement: a sibling part's
    # amendment with the same number and year is a different document.
    include_examples "resolves to", "JIS C 3216-5:2019/AMD 1:2024",
                     "jis-c-3216-5-2019-amendment-1-2024.yaml"
    include_examples "resolves to", "JIS C 0364-5-52:1999/AMD 1:2000",
                     "jis-c-0364-5-52-1999-amendment-1-2000.yaml"
  end

  context "a part-less reference whose document has parts" do
    include_examples "resolves to", "JIS K 6915:2006", "jis-k-6915-2006.yaml"
    include_examples "resolves to", "JIS K 6915", "jis-k-6915-2006.yaml"

    it "still lists every part with all_parts" do
      hits = collection("JIS K 6915").map do |hit|
        hit.pubid.to_s if hit.matches? all_parts: true
      end
      expect(hits.compact).to contain_exactly(
        "JIS K 6915:2006", "JIS K 6915-1:2006", "JIS K 6915-2:2006"
      )
    end

    it "takes the part-less document as the all-parts umbrella" do
      # A part-less index row deserializes with `parts` nil, not [].
      collection("JIS K 6915").find_all_parts
      expect(fetched("jis-k-6915-2006.yaml")).to have_been_made.once
    end
  end

  context "a SYMBOL sub-document" do
    include_examples "resolves to",
                     "JIS L 0001:2024 SYMBOL Wet cleaning process",
                     "jis-l-0001-2024-symbol-wet-cleaning-process.yaml"
    include_examples "resolves to", "JIS L 0001:2024", "jis-l-0001-2024.yaml"
    include_examples "resolves to", "JIS Z 8210:2022/AMD 3:2025R SYMBOL 65700",
                     "jis-z-8210-2022-amd-3-2025r-symbol-65700.yaml"
    include_examples "resolves to", "JIS Z 8210:2022/AMD 3:2025",
                     "jis-z-8210-2022-amendment-3-2025.yaml"
  end

  context "a technical report and a standard with the same number" do
    include_examples "resolves to", "JIS X 0014:1999", "jis-x-0014-1999.yaml"
    include_examples "resolves to", "JIS TR X 0014:1999", "tr-x-0014-1999.yaml"
  end

  context "a reaffirmed edition" do
    # The reaffirmation mark `R` belongs to the edition, like the year.
    include_examples "resolves to", "JIS L 4107:2000", "jis-l-4107-2000r.yaml"
    include_examples "resolves to", "JIS C 9901", "jis-c-9901-2019r.yaml"
  end

  it "returns the matched edition years when the year does not match" do
    expect(collection("JIS K 6915-1:2005").find).to eq [2006]
  end
end
