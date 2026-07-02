require "relaton/ecma/data_fetcher"

describe Relaton::Ecma::DataParser do
  let(:hit) do
    Nokogiri::HTML(
      '<a href="https://ecma-international.org/publications-and-standards/standards/ecma-370/">ECMA-370</a>'
    ).at("a")
  end
  let(:hit_mem) do
    Nokogiri::HTML(<<~HTML).at("div")
      <div class="entry-content-wrapper clearfix">
        <div><section><div><p>2025</p></div></section></div>
        <div><section><div><p>January 2025</p></div></section></div>
        <div><section><div><p>
          <a href="https://ecma-international.org/wp-content/uploads/Ecma-memento-2025-public.pdf">Download</a>
        </p></div></section></div>
      </div>
    HTML
  end

  context "#parse" do
    context "with hit[:href]" do
      subject { described_class.new(hit) }

      it "returns standards", vcr: "ecma_370" do
        items = subject.parse
        expect(items).to be_instance_of Array
        expect(items.size).to eq 7
        expect(items.first).to be_instance_of Relaton::Ecma::ItemData
        expect(items.first.type).to eq "standard"
        expect(items.first.language).to eq ["en"]
        expect(items.first.script).to eq ["Latn"]
        expect(items.first.place.first).to be_instance_of Relaton::Bib::Place
        expect(items.first.docidentifier.first).to be_instance_of Relaton::Bib::Docidentifier
        expect(items.first.title.first).to be_instance_of Relaton::Bib::Title
        expect(items.first.abstract.first).to be_instance_of Relaton::Bib::Abstract
        expect(items.first.date.first).to be_instance_of Relaton::Bib::Date
        expect(items.first.source.first).to be_instance_of Relaton::Bib::Uri
        expect(items.first.relation.first).to be_instance_of Relaton::Bib::Relation
        expect(items.first.edition).to be_instance_of Relaton::Bib::Edition
        expect(items.first.ext).to be_instance_of Relaton::Ecma::Ext
        expect(items.first.ext.doctype).to be_instance_of Relaton::Bib::Doctype
        expect(items.first.ext.flavor).to eq "ecma"
      end
    end

    context "without hit[:href]" do
      subject { described_class.new(hit_mem) }

      it "returns memento" do
        items = subject.parse
        expect(items).to be_instance_of Array
        expect(items.size).to eq 1
        expect(items.first).to be_instance_of Relaton::Ecma::ItemData
        expect(items.first.docidentifier.first).to be_instance_of Relaton::Bib::Docidentifier
        expect(items.first.title.first).to be_instance_of Relaton::Bib::Title
        expect(items.first.date.first).to be_instance_of Relaton::Bib::Date
        expect(items.first.source.first).to be_instance_of Relaton::Bib::Uri
        expect(items.first.ext).to be_instance_of Relaton::Ecma::Ext
        expect(items.first.ext.doctype).to be_instance_of Relaton::Bib::Doctype
        expect(items.first.ext.flavor).to eq "ecma"
      end
    end
  end
end
