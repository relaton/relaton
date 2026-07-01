require "relaton/ieee/data_fetcher"

describe Relaton::Ieee::IdamsParser do
  context "parse" do
    let(:doc) { ::Ieee::Idams::Publication.from_xml source_xml }
    let(:fetcher) { Relaton::Ieee::DataFetcher.new "data", "xml" }
    subject { described_class.new doc, fetcher }
    let(:bibitem) { subject.parse }

    shared_examples "parse file" do |file|
      let(:source_xml) { File.read "fixtures/examples/#{file}.xml" }
      let(:output_file) { "fixtures/#{file}.xml" }
      let(:xml) { bibitem.to_xml bibdata: true }

      it do
        expect(bibitem).to be_instance_of Relaton::Ieee::ItemData
        File.write output_file, xml, encoding: "UTF-8" unless File.exist? output_file
        expect(xml).to be_equivalent_to File.read(output_file, encoding: "UTF-8")
          .gsub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s)
      end
    end

    it_behaves_like "parse file", "08684487"
    it_behaves_like "parse file", "07873195"
    it_behaves_like "parse file", "04152543"
    it_behaves_like "parse file", "05200238"
    it_behaves_like "parse file", "05491847"
    it_behaves_like "parse file", "04140777"
    it_behaves_like "parse file", "00026466"
    it_behaves_like "parse file", "07409855"

    context "abstract sanitization" do
      let(:source_xml) { File.read "fixtures/examples/04140777.xml" }

      it "strips <<ETX>> placeholder from abstract content" do
        articleinfo = doc.volume.article.articleinfo
        articleinfo.abstract.first.value += "<<ETX>>"

        abstract = subject.send(:parse_abstract)
        expect(abstract.size).to eq 1
        expect(abstract.first.content).not_to include "<<ETX>>"
        expect(abstract.first.content).not_to include "ETX"
      end

      it "skips abstract whose content is only a control-char placeholder" do
        articleinfo = doc.volume.article.articleinfo
        articleinfo.abstract.first.value = "<<ETX>>"

        expect(subject.send(:parse_abstract)).to be_empty
      end
    end

    context "backrefs" do
      let(:source_xml) { File.read "fixtures/examples/07873195.xml" }
      let(:xml) { bibitem.to_xml bibdata: true }
      let(:output_file) { "fixtures/baclref_relation.xml" }
      before { fetcher.backrefs["2487"] = "IEEE P650" }

      it do
        File.write output_file, xml, encoding: "UTF-8" unless File.exist? output_file
        expect(xml).to be_equivalent_to File.read(output_file, encoding: "UTF-8")
      end
    end
  end
end
