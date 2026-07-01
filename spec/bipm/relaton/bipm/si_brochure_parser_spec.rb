require "relaton/bipm/si_brochure_parser"

describe Relaton::Bipm::SiBrochureParser do
  context "class methods" do
    it "::parse" do
      data_parser = double "data_parser"
      expect(data_parser).to receive(:parse)
      expect(described_class).to receive(:new).and_return data_parser
      described_class.parse :data_fetcher
    end
  end

  context "instance methods" do
    let(:index) { double "index" }
    let(:errors) { Hash.new(true) }
    let(:data_fetcher) { double "data_fetcher", output: "data", ext: "yaml", files: [], index: index, errors: errors }
    subject { described_class.new data_fetcher }

    it "#parse_si_brochure" do
      allow(Dir).to receive(:[]).with("bipm-si-brochure/_site/documents/*.rxl")
        .and_return [
          "fixtures/si_brochure/si-brochure-en.rxl",
          "fixtures/si_brochure/si-brochure-fr.rxl",
        ]
      allow(File).to receive(:exist?).and_call_original
      expect(File).to receive(:exist?).with("data/si-brochure.yaml").and_return false, true

      expect(data_fetcher).to receive(:write_file) do |path, item, opt|
        expect(path).to eq "data/si-brochure.yaml"
        p = if opt[:warn_duplicate]
              "fixtures/#{path.sub('brochure', 'brochure_1')}"
            else
              "fixtures/#{path}"
            end
        yaml = item.to_yaml
        File.write p, yaml, encoding: "UTF-8" unless File.exist? p
        hash = YAML.load_file(p)
        expect(YAML.safe_load(yaml)).to eq hash
      end.twice

      allow(File).to receive(:read).and_wrap_original do |m, path|
        m.call path.sub(/^data\/si-brochure\.yaml/, "fixtures/data/si-brochure_1.yaml")
      end

      expect(index).to receive(:add_or_update)
        .with({group: "SI", type: "Brochure", part: "1" }, "data/si-brochure.yaml").twice
      subject.parse
    end

    context "#fix_si_brochure_id" do
      it "docnumber is defined" do
        hash = {
          "id" => "BIPMBrochure", "docnumber" => "Brochure",
          "docidentifier" => [
            { "type" => "BIPM", "content" => "BIPM Brochure Partie 1", "language" => "fr" },
            { "type" => "BIPM", "content" => "BIPM Brochure Part 1", "language" => "en" }
          ]
        }
        item = Relaton::Bipm::Item.from_yaml hash.to_yaml
        subject.fix_si_brochure_id item
        expect(item.id).to eq "BIPMSIBrochurePart1"
        expect(item.docnumber).to eq "SI Brochure Part 1"
        expect(item.docidentifier[0].content).to eq("BIPM SI Brochure Partie 1")
        expect(item.docidentifier[0].primary).to be true
        expect(item.docidentifier[1].content).to eq("BIPM SI Brochure Part 1")
        expect(item.docidentifier[1].primary).to be true
      end

      it "docnumber is not defined" do
        hash = {
          "id" => "BIPMBrochure",
          "docidentifier" => [
            { "type" => "BIPM", "content" => "BIPM Brochure Partie 1", "language" => "fr" },
            { "type" => "BIPM", "content" => "BIPM Brochure Part 1", "language" => "en" }
          ]
        }
        item = Relaton::Bipm::Item.from_yaml hash.to_yaml
        subject.fix_si_brochure_id item
        expect(item.id).to eq "BIPMSIBrochurePart1"
        expect(item.docnumber).to eq "SI Brochure Part 1"
        expect(item.docidentifier[0].content).to eq("BIPM SI Brochure Partie 1")
        expect(item.docidentifier[0].primary).to be true
        expect(item.docidentifier[1].content).to eq("BIPM SI Brochure Part 1")
        expect(item.docidentifier[1].primary).to be true
      end
    end

    context "#update_id" do
      it "updates id" do
        hash = {
          "docidentifier" => [
            { "type" => "BIPM", "content" => "BIPM Brochure Partie 1", "language" => "fr" },
            { "type" => "BIPM", "content" => "BIPM Brochure Part 1", "language" => "en" }
          ]
        }
        item = Relaton::Bipm::Item.from_yaml hash.to_yaml
        subject.update_id item
        expect(item.docidentifier[0].content).to eq("BIPM SI Brochure Partie 1")
        expect(item.docidentifier[1].content).to eq("BIPM SI Brochure Part 1")
      end
    end

    context "#primary_id" do
      it "returns EN primary id" do
        hash = {
          "docidentifier" => [
            { "type" => "BIPM", "content" => "BIPM SI Brochure Partie 1", "primary" => true, "language" => "fr" },
            { "type" => "BIPM", "content" => "BIPM SI Brochure Part 1", "primary" => true, "language" => "en" }
          ]
        }
        item = Relaton::Bipm::Item.from_yaml hash.to_yaml
        expect(subject.primary_id(item)).to eq("BIPM SI Brochure Part 1")
      end

      it "returns primary id without language" do
        hash = {
          "docidentifier" => [
            { "type" => "BIPM", "content" => "BIPM SI Brochure Partie 1", "primary" => true, "language" => "fr" },
            { "type" => "BIPM", "content" => "BIPM SI Brochure Part 1", "primary" => true }
          ]
        }
        item = Relaton::Bipm::Item.from_yaml hash.to_yaml
        expect(subject.primary_id(item)).to eq("BIPM SI Brochure Part 1")
      end
    end
  end
end
