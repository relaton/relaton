require "jing"

RSpec.describe Relaton::Bipm::Bibliography do
  context "raise RequestError" do
    it "fetch from GitHub" do
      index = double "index"
      expect(index).to receive(:search).and_return [{ id: { year: "156" }, path: "data/doc.yaml" }]
      expect(Relaton::Index).to receive(:find_or_create).with(
        :bipm,
        url: "https://raw.githubusercontent.com/relaton/relaton-data-bipm/main/index2.zip",
        file: "index2.yaml", id_keys: %i[group type number year corr part append]
      ).and_return index
      agent = double(:agent)
      expect(agent).to receive(:get).and_raise Mechanize::ResponseCodeError.new(Mechanize::Page.new)
      expect(Mechanize).to receive(:new).and_return agent
      expect do
        Relaton::Bipm::Bibliography.search "Metrologia"
      end.to raise_error Relaton::RequestError
    end
  end

  context "bib instance" do
    subject do
      Relaton::Bipm::Item.from_yaml File.read("spec/fixtures/bipm_item.yml", encoding: "UTF-8")
    end

    it "returns XML" do
      file = "spec/fixtures/bipm_item.xml"
      xml = subject.to_xml bibdata: true
      File.write file, xml, encoding: "UTF-8" unless File.exist? file
      expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
      schema = Jing.new "grammars/relaton-bipm-compile.rng"
      errors = schema.validate file
      expect(errors).to eq []
    end

    it "returns Hash" do
      hash = YAML.safe_load subject.to_yaml
      file = "spec/fixtures/bipm.yaml"
      File.write file, hash.to_yaml, encoding: "UTF-8" unless File.exist? file
      expect(hash).to eq YAML.load_file file
    end

    xit "returns AsciiBib" do
      bib = subject.to_asciibib
      file = "spec/fixtures/asciibib.adoc"
      File.write file, bib, encoding: "UTF-8" unless File.exist? file
      expect(bib).to eq File.read(file, encoding: "UTF-8")
    end
  end
end
