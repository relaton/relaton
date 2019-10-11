module Relaton
  class TestProcessor < Relaton::Processor
    def initialize; end
  end
end

RSpec.describe Relaton::Processor do
  it "initialize should be implemented" do
    expect { Relaton::Processor.new }.to raise_error StandardError
  end

  context "instance of processor" do
    subject { Relaton::TestProcessor.new }

    it "get method should be implemented" do
      expect { subject.get "code", nil, {} }.to raise_error StandardError
    end

    it "from_xml method should be implemented" do
      expect { subject.from_xml "" }.to raise_error StandardError
    end

    it "hash_to_bib method should be implemented" do
      expect { subject.hash_to_bib({}) }.to raise_error StandardError
    end
  end
end
