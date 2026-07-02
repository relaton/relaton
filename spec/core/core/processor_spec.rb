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
end
