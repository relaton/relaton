RSpec.describe Relaton::Core::Processor do
  subject do
    Class.new(described_class) do
      def initialize; end
    end.new
  end

  it "raises an error when initialized" do
    expect { described_class.new }.to raise_error "This is an abstract class!"
  end

  it "raises an error when calling get" do
    expect { subject.get("code", "date", {}) }.to raise_error "This is an abstract class!"
  end

  it "raises an error when calling fetch_data" do
    expect { subject.fetch_data("source", {}) }.to raise_error "This is an abstract class!"
  end

  it "raises an error when calling from_xml" do
    expect { subject.from_xml("<xml/>") }.to raise_error "This is an abstract class!"
  end

  it "raises an error when calling from_yaml" do
    expect { subject.from_yaml({}) }.to raise_error "This is an abstract class!"
  end

  it "raises an error when calling grammar_hash" do
    expect { subject.grammar_hash }.to raise_error "This is an abstract class!"
  end

  it "returns default number of workers" do
    expect(subject.threads).to eq 10
  end

  describe "pubid cache key" do
    def processor(**ivars)
      Class.new(described_class) do
        define_method(:initialize) do
          @prefix = "ISO"
          ivars.each { |k, v| instance_variable_set :"@#{k}", v }
        end
      end.new
    end

    it "has no pubid class without a pubid declaration" do
      expect(processor.pubid_class).to be_nil
      expect(processor.cache_key("ISO 123", nil, {})).to be_nil
    end

    it "takes the pubid class from @pubid_flavor" do
      expect(processor(pubid_flavor: :Iso).pubid_class)
        .to be Pubid::Iso::Identifier
    end

    it "takes the pubid class from @pubid_identifier, without prefixes" do
      pr = processor(pubid_identifier: :Iso)
      expect(pr.pubid_class).to be Pubid::Iso::Identifier
      expect(pr.prefixes).to eq ["ISO"]
    end

    it "folds the year into the key" do
      key = processor(pubid_flavor: :Iso).cache_key("ISO 19115-1", "2014", {})
      expect(key).to eq Pubid::Iso::Identifier.parse("ISO 19115-1:2014")
    end

    it "folds all_parts into the key" do
      key = processor(pubid_flavor: :Iso)
        .cache_key("ISO 19115-1", nil, { all_parts: true })
      expect(key).to be_all_parts
      expect(key.number.to_s).to eq "19115"
    end

    it "keeps the publication date range out of the key" do
      pr = processor(pubid_flavor: :Iso)
      ranged = pr.cache_key("ISO 19115-1", nil, publication_date_after: "2020")
      expect(ranged).to eq pr.cache_key("ISO 19115-1", nil, {})
    end

    it "raises on an unparseable reference" do
      expect { processor(pubid_flavor: :Iso).cache_key("ISO", nil, {}) }
        .to raise_error Pubid::Errors::ParseError
    end
  end
end
