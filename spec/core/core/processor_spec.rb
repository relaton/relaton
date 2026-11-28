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

    it "gives no key for a reference the grammar cannot read (relaton#235)" do
      expect(processor(pubid_flavor: :Iso).cache_key("ISO", nil, {})).to be_nil
    end

    context "#query_pubid" do
      it "returns the routed parse itself" do
        routed = Pubid::Iso::Identifier.parse "ISO 19115-1"
        pr = processor(pubid_flavor: :Iso)
        expect(pr).not_to receive(:cache_pubid)
        expect(pr.query_pubid("ISO 19115-1", {}, routed)).to be routed
      end

      it "parses the reference when there is no routed parse" do
        expect(processor(pubid_flavor: :Iso).query_pubid("ISO 19115-1"))
          .to eq Pubid::Iso::Identifier.parse("ISO 19115-1")
      end

      it "is nil when the flavor gives no pubid" do
        pr = processor(pubid_flavor: :Iso)
        allow(pr).to receive(:cache_pubid).and_return nil
        expect(pr.query_pubid("ISO 19115-1")).to be_nil
      end

      it "is nil for a processor with no pubid class" do
        expect(processor.query_pubid("ISO 19115-1")).to be_nil
      end
    end

    it "keys the cache with the given pubid without parsing again" do
      routed = Pubid::Iso::Identifier.parse "ISO 19115-1"
      pr = processor(pubid_flavor: :Iso)
      expect(pr).not_to receive(:cache_pubid)
      key = pr.cache_key("ISO 19115-1", "2014", {}, routed)
      expect(key.to_s).to eq "ISO 19115-1:2014"
      expect(routed.to_s).to eq "ISO 19115-1"
    end

    # relaton#205 PR 3: the publishers after the lead, in the order the parsed
    # pubid holds them (pubid#472: as printed).
    context "#copublishers" do
      def copublishers(ref, flavor)
        processor(pubid_flavor: flavor)
          .copublishers(Pubid.const_get(flavor)::Identifier.parse(ref))
      end

      it "reads them from an ISO pubid" do
        expect(copublishers("ISO/IEC/IEEE 15288", :Iso)).to eq %w[IEC IEEE]
      end

      it "reads them from an IEC pubid" do
        expect(copublishers("IEC/ISO 31010", :Iec)).to eq %w[ISO]
      end

      it "reads them from a supplement" do
        expect(copublishers("ISO/IEC 27001:2022/Amd 1:2024", :Iso)).to eq %w[IEC]
      end

      it "reads them through an all-parts wrapper" do
        expect(copublishers("ISO/IEC 27001 (all parts)", :Iso)).to eq %w[IEC]
      end

      it "is empty for a single publisher" do
        expect(copublishers("ISO 8601", :Iso)).to eq []
      end
    end

    describe "parse memoization (relaton#633)" do
      let(:memo_processor) { processor(pubid_flavor: :Iso) }

      # Counts real parses through the real identifier class; `parse` is
      # the class's own singleton method, so alias it aside and restore it
      # afterwards (define-then-remove would lose the original).
      def with_parse_counter
        klass = Pubid::Iso::Identifier
        sc = klass.singleton_class
        sc.alias_method :parse_without_counter, :parse
        calls = []
        klass.define_singleton_method(:parse) do |ref|
          calls << ref
          klass.send(:parse_without_counter, ref)
        end
        yield calls
      ensure
        sc.alias_method :parse, :parse_without_counter
        sc.send(:remove_method, :parse_without_counter)
      end

      it "answers the same instance for a repeated reference" do
        first = memo_processor.cache_pubid("ISO 8601")
        second = memo_processor.cache_pubid("ISO 8601")
        expect(first).not_to be_nil
        expect(second).to equal(first)
      end

      it "parses a reference once for repeated calls" do
        with_parse_counter do |calls|
          3.times { memo_processor.cache_pubid("ISO 8601-1") }
          expect(calls.size).to eq 1
        end
      end

      it "memoizes a miss without re-parsing it" do
        with_parse_counter do |calls|
          2.times { memo_processor.cache_pubid("NOT A STANDARD") }
          expect(calls.size).to eq 1
        end
      end

      it "keys the memo per identifier class" do
        iso = processor(pubid_flavor: :Iso).cache_pubid("ISO 31000")
        iec = processor(pubid_flavor: :Iec).cache_pubid("ISO 31000")
        expect(iso).not_to equal(iec)
      end

      it "evicts the oldest entries once the memo is full" do
        limit = described_class::MEMO_LIMIT
        first = memo_processor.cache_pubid("ISO 1111")
        (0...limit + 50).each { |i| memo_processor.cache_pubid("ISO 2#{i}") }
        latest = memo_processor.cache_pubid("ISO 2#{limit + 49}")
        reread = memo_processor.cache_pubid("ISO 1111")
        expect(latest).not_to be_nil
        expect(reread).not_to equal(first)
      end
    end
  end
end
