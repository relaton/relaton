# frozen_string_literal: true

RSpec.describe Relaton::Omg::Docidentifier do
  def docid(content)
    described_class.new(type: "OMG", content: content, primary: true)
  end

  it "parses its content into a pubid" do
    expect(docid("OMG AMI4CCM 1.1").pubid)
      .to be_a Pubid::Omg::Identifiers::Specification
  end

  it "reads the document part" do
    pubid = docid("OMG UML 2.1.1 Superstructure").pubid

    expect(pubid.acronym).to eq "UML"
    expect(pubid.version).to eq "2.1.1"
    expect(pubid.part).to eq "Superstructure"
  end

  # 30 of the 270 acronyms in the OMG catalog (https://www.omg.org/spec/) carry
  # a hyphen, a slash, a plus, or start in lower case. The acronym is the URL
  # segment, so it must come back verbatim (pubid PR #376).
  {
    "OMG DDS-XTypes 1.3" => "DDS-XTypes",
    "OMG DDSI-RTPS 2.5" => "DDSI-RTPS",
    "OMG EDMC-FIBO/BE 1.1" => "EDMC-FIBO/BE",
    "OMG VSIPL++ 1.3" => "VSIPL++",
    "OMG smartant 1.0" => "smartant",
  }.each do |ref, acronym|
    it "reads the acronym of #{ref.inspect}" do
      expect(docid(ref).pubid&.acronym).to eq acronym
    end
  end

  it "keeps a non-OMG value verbatim, with no pubid" do
    id = docid("ISBN 978-92-67-10790-9")

    expect(id.pubid).to be_nil
    expect(id.content).to eq "ISBN 978-92-67-10790-9"
  end

  it "keeps an unparseable OMG-looking value verbatim, with no pubid" do
    id = docid("OMG Model Driven Architecture Guide rev. 2.0")

    expect(id.pubid).to be_nil
    expect(id.content).to eq "OMG Model Driven Architecture Guide rev. 2.0"
  end

  # OMG models no date. The version is the discriminator, so the
  # version-agnostic ("most recent") reference drops the version.
  describe "#remove_date!" do
    {
      "OMG AMI4CCM 1.1" => "OMG AMI4CCM",
      "OMG AMI4CCM" => "OMG AMI4CCM",
      "OMG UML 2.5 beta 1" => "OMG UML",
      "OMG UML 2.1.1 Superstructure" => "OMG UML Superstructure",
    }.each do |from, to|
      it "renders #{from.inspect} as #{to.inspect}" do
        id = docid(from)
        id.remove_date!
        expect(id.content).to eq to
      end
    end

    it "leaves a verbatim value unchanged" do
      id = docid("ISBN 978-92-67-10790-9")
      id.remove_date!
      expect(id.content).to eq "ISBN 978-92-67-10790-9"
    end
  end

  describe "#remove_part!" do
    {
      "OMG UML 2.1.1 Superstructure" => "OMG UML 2.1.1",
      "OMG AMI4CCM 1.1" => "OMG AMI4CCM 1.1",
    }.each do |from, to|
      it "renders #{from.inspect} as #{to.inspect}" do
        id = docid(from)
        id.remove_part!
        expect(id.content).to eq to
      end
    end

    it "leaves a verbatim value unchanged" do
      id = docid("ISBN 978-92-67-10790-9")
      id.remove_part!
      expect(id.content).to eq "ISBN 978-92-67-10790-9"
    end
  end

  # An OMG part is a volume or a format name, so there is no all-parts form.
  describe "#to_all_parts!" do
    it "leaves the content unchanged" do
      id = docid("OMG UML 2.1.1 Superstructure")
      id.to_all_parts!
      expect(id.content).to eq "OMG UML 2.1.1 Superstructure"
    end
  end

  it "does not re-parse the rendered string on a mutation" do
    id = docid("OMG UML 2.1.1 Superstructure")
    expect(Pubid::Omg::Identifier).not_to receive(:parse)
    id.remove_date!
  end
end
