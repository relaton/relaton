describe Relaton::Bib::PlainDate do
  describe ".cast" do
    it "returns ::Date for a plain ISO date string" do
      result = described_class.cast("2018-04-15")
      expect(result).to be_a(::Date)
      expect(result.iso8601).to eq "2018-04-15"
    end

    it "keeps a datetime string with Z as ::DateTime (relaton#636)" do
      result = described_class.cast("2018-04-15T00:00:00Z")
      expect(result).to be_a(::DateTime)
      expect(described_class.serialize(result)).to eq "2018-04-15T00:00:00Z"
    end

    it "keeps a datetime string with an offset as ::DateTime" do
      result = described_class.cast("2018-04-15T12:34:56+05:30")
      expect(result).to be_a(::DateTime)
      expect(described_class.serialize(result)).to eq "2018-04-15T12:34:56+05:30"
    end

    it "keeps xs:date precision for a date string with a zone offset" do
      result = described_class.cast("2018-04-15+05:30")
      expect(result).to be_a(::Date)
      expect(result).not_to be_a(::DateTime)
      expect(result.iso8601).to eq "2018-04-15"
    end

    it "passes through a ::Date unchanged" do
      d = ::Date.new(2018, 4, 15)
      expect(described_class.cast(d)).to eq d
    end

    it "keeps a ::DateTime input as ::DateTime" do
      dt = ::DateTime.new(2018, 4, 15, 12, 34, 56)
      result = described_class.cast(dt)
      expect(result).to be_a(::DateTime)
      expect(described_class.serialize(result)).to eq "2018-04-15T12:34:56Z"
    end

    it "returns nil for nil" do
      expect(described_class.cast(nil)).to be_nil
    end
  end
end
