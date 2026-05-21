describe Relaton::Core::ArrayWrapper do
  include Relaton::Core::ArrayWrapper

  describe "#array" do
    it "returns array when given array" do
      expect(array([1, 2, 3])).to eq [1, 2, 3]
    end

    it "wraps non-array into array" do
      expect(array(5)).to eq [5]
    end

    it "returns empty array when given nil" do
      expect(array(nil)).to eq []
    end
  end
end
