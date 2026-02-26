# frozen_string_literal: true

describe Relaton::Jis::Docidentifier do
  subject do
    described_class.new(
      content: "JIS A 1301-1:2020", type: "JIS", primary: true,
    )
  end

  it "#remove_part!" do
    subject.remove_part!
    expect(subject.content).to eq "JIS A 1301:2020"
  end

  it "#remove_date!" do
    subject.remove_date!
    expect(subject.content).to eq "JIS A 1301-1"
  end

  it "#to_all_parts!" do
    subject.to_all_parts!
    expect(subject.content).to eq "JIS A 1301 (all parts)"
  end

  context "when no part or date" do
    subject do
      described_class.new(content: "JIS A 1301", type: "JIS", primary: true)
    end

    it "#remove_part! is a no-op" do
      subject.remove_part!
      expect(subject.content).to eq "JIS A 1301"
    end

    it "#remove_date! is a no-op" do
      subject.remove_date!
      expect(subject.content).to eq "JIS A 1301"
    end
  end
end
