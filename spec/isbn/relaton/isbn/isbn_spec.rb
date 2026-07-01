describe Relaton::Isbn::Isbn do
  it "creates ISBN object" do
    subj = described_class.new("ISBN 0-12-064481-9")
    expect(subj).to be_instance_of Relaton::Isbn::Isbn
    expect(subj.instance_variable_get(:@isbn)).to eq "0120644819"
  end

  context "parse ISBN" do
    it "with 10-digit ISBN" do
      expect(described_class.new("ISBN 0-12-064481-9").parse).to eq "9780120644810"
    end

    it "with 13-digit ISBN" do
      expect(described_class.new("978-0-12-064481-0").parse).to eq "9780120644810"
    end

    it "with incorrect ISBN" do
      expect(described_class.new("978-0-12-064481-").parse).to be_nil
    end

    it "with incorrect 10-digits ISBN" do
      expect(described_class.new("0-12-064481-8").parse).to be_nil
    end

    it "with incorrect 13-digits ISBN" do
      expect(described_class.new("978-0-12-064481-1").parse).to be_nil
    end

    it "with nil" do
      expect(described_class.new(nil).parse).to be_nil
    end

    context "with prefix" do
      it "ISBN" do
        expect(described_class.new("ISBN 0-12-064481-9").parse).to eq "9780120644810"
      end

      it "isbn:" do
        expect(described_class.new("isbn:0-12-064481-9").parse).to eq "9780120644810"
      end
    end
  end

  context "check ISBN" do
    it "10-digit ISBN" do
      expect(described_class.new("0-12-064481-9").check?).to be true
    end

    it "13-digit ISBN" do
      expect(described_class.new("978-0-12-064481-0").check?).to be true
    end

    it "incorrect 10-digits ISBN" do
      expect(described_class.new("0-12-064481-8").check?).to be false
    end

    it "incorrect 13-digits ISBN" do
      expect(described_class.new("978-0-12-064481-1").check?).to be false
    end

    it "incorrect ISBN" do
      expect(described_class.new("978-0-12-064481-").check?).to be false
    end
  end
end
