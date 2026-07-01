require "relaton/ecma/data_fetcher"

describe Relaton::Ecma::StandardParser do
  let(:hit) do
    Nokogiri::HTML(
      '<a href="https://ecma-international.org/publications-and-standards/standards/ecma-370/">ECMA-370</a>'
    ).at("a")
  end
  let(:translations_doc) do
    Nokogiri::HTML <<~HTML
      <html>
        <body>
          <div class="ecma-item-archives-wrapper">
            <h2>Translations</h2>
            <ul class="ecma-item-archives">
              <li>
                <span>ECMA-370, Japanese version, 1st edition</span>
                <span>
                  <a href="https://ecma-international.org/wp-content/uploads/ECMA-370_1st_edition_japanese_version.pdf">Download</a>
                </span>
              </li>
              <li>
                <span>ECMA-370, Japanese version, 2nd edition</span>
                <span>
                  <a href="https://ecma-international.org/wp-content/uploads/ECMA-370_2nd_edition_december_2006_japanese.pdf">Download</a>
                </span>
              </li>
              <li>
                <span>ECMA-370, Japanese version, 3rd edition</span>
                <span>
                  <a href="https://ecma-international.org/wp-content/uploads/ECMA-370_3rd_edition_december_2008_japanese.pdf">Download</a>
                </span>
              </li>
            </ul>
          </div>
        </body>
      </html>
    HTML
  end

  let(:empty_doc) { Nokogiri::HTML "<html><body></body></html>" }

  subject { described_class.new(hit: hit, doc: empty_doc) }

  context "#fetch_source" do
    context "without pdf link" do
      it "with hit[:href]" do
        source = subject.fetch_source
        expect(source.first).to be_instance_of Relaton::Bib::Uri
        expect(source.first.type).to eq "src"
        expect(source.first.content.to_s).to eq "https://ecma-international.org/publications-and-standards/standards/ecma-370/"
      end
    end

    context "with pdf link" do
      let(:doc) do
        Nokogiri::HTML <<~HTML
          <html>
            <body>
              <div class="ecma-item-content-wrapper">
                <span><a href="link">link</a></span>
              </div>
            </body>
          </html>
        HTML
      end

      it "returns source with pdf" do
        parser = described_class.new(hit: hit, doc: doc)
        source = parser.fetch_source
        expect(source.size).to be >= 2
        expect(source[0].type).to eq "src"
        expect(source[1].type).to eq "pdf"
        expect(source[1].content.to_s).to eq "link"
      end
    end
  end

  context "#translation_source" do
    it "Japanese" do
      parser = described_class.new(hit: hit, doc: translations_doc)
      translations = parser.translation_source

      expect(translations).to be_instance_of Array
      expect(translations.first).to be_instance_of Hash
      expect(translations.first[:ed]).to eq "1"
      expect(translations.first[:source]).to be_instance_of Relaton::Bib::Uri
      expect(translations.first[:source].type).to eq "pdf"
      expect(translations.first[:source].content).to eq "https://ecma-international.org/wp-content/uploads/ECMA-370_1st_edition_japanese_version.pdf"
      expect(translations.first[:source].language).to eq "ja"
      expect(translations.first[:source].script).to eq "Jpan"
    end
  end

  it "#fetch_title" do
    doc = Nokogiri::HTML <<~HTML
      <html>
        <body>
          <div><p class="ecma-item-short-description">title</p></div>
        </body>
      </html>
    HTML
    parser = described_class.new(hit: hit, doc: doc)

    title = parser.fetch_title
    expect(title.first).to be_instance_of Relaton::Bib::Title
    expect(title.first.content).to eq "title"
    expect(title.first.language).to eq "en"
    expect(title.first.script).to eq "Latn"
  end

  it "#fetch_abstract" do
    doc = Nokogiri::HTML <<~HTML
      <html>
        <body>
          <div class="ecma-item-content"><p>Abstract 1</p></div>
          <div class="ecma-item-content"><p>abstract 2</p></div>
        </body>
      </html>
    HTML
    parser = described_class.new(hit: hit, doc: doc)

    abstract = parser.fetch_abstract

    expect(abstract).to be_instance_of Array
    expect(abstract.first).to be_instance_of Relaton::Bib::Abstract
    expect(abstract.first.content).to eq "Abstract 1\nabstract 2"
  end

  it "#fetch_date" do
    doc = Nokogiri::HTML <<~HTML
      <html>
        <body>
          <p class="ecma-item-edition">1st edition, December 2022</p>
        </body>
      </html>
    HTML
    parser = described_class.new(hit: hit, doc: doc)

    date = parser.fetch_date

    expect(date).to be_instance_of Array
    expect(date.first).to be_instance_of Relaton::Bib::Date
    expect(date.first.at.to_s).to eq "2022-12"
    expect(date.first.type).to eq "published"
  end

  it "#fetch_relation" do
    doc = Nokogiri::HTML <<~HTML
      <html>
        <body>
          <div>
            <ul class="ecma-item-archives">
              <li>
                <span>ECMA TR/27, 1st edition, March 1985</span>
                <span><a href="https://www.ecma-international.org/wp-content/uploads/ECMA_TR-27_1st_edition_march-1985-1.pdf">Download</a></span>
              </li>
            </ul>
          </div>
        </body>
      </html>
    HTML
    parser = described_class.new(hit: hit, doc: doc)

    relation = parser.fetch_relation

    expect(relation).to be_instance_of Array
    expect(relation.size).to eq 1
    expect(relation.first).to be_instance_of Relaton::Bib::Relation
    expect(relation.first.type).to eq "updates"
    expect(relation.first.bibitem).to be_instance_of Relaton::Ecma::ItemData
    expect(relation.first.bibitem.docidentifier.first.content).to eq "ECMA TR/27"
    expect(relation.first.bibitem.docidentifier.first.type).to eq "ECMA"
    expect(relation.first.bibitem.docidentifier.first.primary).to be true
    expect(relation.first.bibitem.edition.content).to eq "1"
    expect(relation.first.bibitem.date.first.at.to_s).to eq "1985-03"
    expect(relation.first.bibitem.date.first.type).to eq "published"
    expect(relation.first.bibitem.source.first.type).to eq "pdf"
    expect(relation.first.bibitem.source.first.content.to_s).to eq(
      "https://www.ecma-international.org/wp-content/uploads/ECMA_TR-27_1st_edition_march-1985-1.pdf",
    )
  end

  context "#fetch_edition" do
    shared_examples "edition" do |text, expected|
      it do
        doc = Nokogiri::HTML <<~HTML
          <html>
            <body>
              <p class="ecma-item-edition">#{text}</p>
            </body>
          </html>
        HTML
        parser = described_class.new(hit: hit, doc: doc)

        edition = parser.fetch_edition

        if expected
          expect(edition).to be_instance_of Relaton::Bib::Edition
          expect(edition.content).to eq expected
        else
          expect(edition).to be_nil
        end
      end
    end

    it_behaves_like "edition", "1st edition, December 2022", "1"
    it_behaves_like "edition", "2nd edition, December 2022", "2"
    it_behaves_like "edition", "3rd edition, December 2022", "3"
    it_behaves_like "edition", "4th edition, December 2022", "4"
    it_behaves_like "edition", "1 edition, December 2022", nil
  end
end
