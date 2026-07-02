# frozen_string_literal: true

describe Relaton::Jis::Bibliography do
  context "class methods" do
    context ".get" do
      it "returns nil if not found" do
        expect(described_class).to receive(:search).and_return nil
        expect do
          expect(described_class.get("JIS X 0208")).to be_nil
        end.to output(/\[relaton-jis\] INFO: \(JIS X 0208\) Not found\./).to_stderr_from_any_process
      end
    end
  end

  it "searches JIS" do
    result = described_class.search "JIS X 0208"
    expect(result).to be_instance_of(Relaton::Jis::HitCollection)
    expect(result.size).to eq(2)
    expect(result.first).to be_instance_of(Relaton::Jis::Hit)
    expect(result[0].pubid.to_s).to eq("JIS X 0208:1997")
  end

  context "get" do
    it "JIS without year", vcr: { cassette_name: "get" } do
      file = "fixtures/jis_x_0208.xml"
      bib = described_class.get "JIS X 0208"
      xml = bib.to_xml bibdata: true
      File.write file, xml, encoding: "UTF-8" unless File.exist? file
      expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
        .gsub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s)
      # TODO: re-enable schema validation once upstream subdivision serialization is fixed
      # schema = Jing.new "../../grammar/relaton-jis-compile.rng"
      # errors = schema.validate file
      # expect(errors).to eq []
    end

    it "JIS with year", vcr: { cassette_name: "get" } do
      expect do
        bib = described_class.get "JIS X 0208:1997"
        expect(bib.docidentifier.first.content).to eq "JIS X 0208:1997"
      end.to output(/\[relaton-jis\] INFO: \(JIS X 0208:1997\) Found: `JIS X 0208:1997`/).to_stderr_from_any_process
    end

    it "JIS with year as argument", vcr: { cassette_name: "get" } do
      bib = described_class.get "JIS X 0208", "1997"
      expect(bib.docidentifier.first.content).to eq "JIS X 0208:1997"
    end

    it "JIS with wrong year", vcr: { cassette_name: "get" } do
      expect do
        bib = described_class.get "JIS X 0208", "1998"
        expect(bib).to be_nil
      end.to output(/TIP: No match for edition year `1998`/).to_stderr_from_any_process
    end

    it "JIS withdrawn", vcr: { cassette_name: "withdrawn" } do
      bib = described_class.get "JIS Z 8201"
      expect(bib.docidentifier.first.content).to eq "JIS Z 8201"
    end

    it "TR", vcr: { cassette_name: "tr" } do
      bib = described_class.get "TR A 0001:1996"
      expect(bib.docidentifier.first.content).to eq "TR A 0001:1996"
    end

    it "does not find", vcr: "not_found" do
      expect do
        bib = described_class.get "JIS Z 0000"
        expect(bib).to be_nil
      end.to output(/Not found/).to_stderr_from_any_process
    end

    context "with all parts", vcr: { cassette_name: "get_all_parts" } do
      it "EN" do
        file = "fixtures/jis_b_0060_all_parts.xml"
        bib = described_class.get "JIS B 0060 (all parts)"
        xml = bib.to_xml bibdata: true
        File.write file, xml, encoding: "UTF-8" unless File.exist? file
        expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
          .gsub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s)
      end

      it "JP" do
        bib = described_class.get "JIS B 0060 (規格群)"
        expect(bib.docidentifier.first.content).to eq "JIS B 0060 (all parts)"
      end

      it "option" do
        bib = described_class.get "JIS B 0060", nil, all_parts: true
        expect(bib.docidentifier.first.content).to eq "JIS B 0060 (all parts)"
      end
    end
  end
end
