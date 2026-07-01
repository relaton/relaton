describe Relaton::Core::HashKeysSymbolizer do
  include Relaton::Core::HashKeysSymbolizer

  describe "#symbolize_hash_keys" do
    it "symbolizes keys in a simple hash" do
      input = { "a" => 1, "b" => 2 }
      expected = { a: 1, b: 2 }
      expect(symbolize_hash_keys(input)).to eq expected
    end

    it "symbolizes keys in a nested hash" do
      input = { "a" => { "b" => 2, "c" => { "d" => 4 } } }
      expected = { a: { b: 2, c: { d: 4 } } }
      expect(symbolize_hash_keys(input)).to eq expected
    end

    it "symbolizes keys in an array of hashes" do
      input = [{ "a" => 1 }, { "b" => 2 }]
      expected = [{ a: 1 }, { b: 2 }]
      expect(symbolize_hash_keys(input)).to eq expected
    end

    it "handles mixed structures" do
      input = {
        "a" => [{ "b" => 2 }, { "c" => { "d" => 4 } }],
        "e" => 5
      }
      expected = {
        a: [{ b: 2 }, { c: { d: 4 } }],
        e: 5
      }
      expect(symbolize_hash_keys(input)).to eq expected
    end
  end
end
