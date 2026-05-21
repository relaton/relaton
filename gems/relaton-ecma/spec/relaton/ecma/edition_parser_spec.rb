require "relaton/ecma/data_fetcher"

describe Relaton::Ecma::EditionParser do
  let(:empty_doc) { Nokogiri::HTML "<html><body></body></html>" }
  let(:bib) { { type: "standard", language: ["en"], script: ["Latn"] } }

  subject { described_class.new(doc: empty_doc, bib: bib) }

  context "#edition_id_parts" do
    shared_examples "edition id parts" do |text, docid, edition, date, volume|
      it do
        id, ed, dt, vol = subject.edition_id_parts(text)

        expect(id).to eq docid
        expect(ed).to eq edition
        expect(vol).to eq volume
        expect(dt).to be_instance_of Array
        if date
          expect(dt.size).to eq 1
          expect(dt.first).to be_instance_of Relaton::Bib::Date
          expect(dt.first.at.to_s).to eq date
          expect(dt.first.type).to eq "published"
        else
          expect(dt).to be_empty
        end
      end
    end

    it_behaves_like "edition id parts", "ECMA-402 1st edition, December 2012", "ECMA-402", "1", "2012-12", nil
    it_behaves_like "edition id parts", "ECMA-402, 2nd edition, May 2011", "ECMA-402", "2", "2011-05", nil
    it_behaves_like "edition id parts", "ECMA-402 3rd edition, December 2012", "ECMA-402", "3", "2012-12", nil
    it_behaves_like "edition id parts", "ECMA-402 4th edition, December 2012", "ECMA-402", "4", "2012-12", nil
    it_behaves_like "edition id parts", "ECMA-410, 2nd edition. June 2015", "ECMA-410", "2", "2015-06", nil
    it_behaves_like "edition id parts", "ECMA-269, 1st edition", "ECMA-269", "1", nil, nil
    it_behaves_like "edition id parts", "ECMA-269, Volume 1, 3rd edition, December 1998", "ECMA-269", "3", "1998-12", "1"
    it_behaves_like "edition id parts", "ECMA-269, 9th edition, December 2011, changes since the previous edition", "ECMA-269", "9", "2011-12", nil
  end

  context "#edition_source" do
    it "pdf" do
      doc = Nokogiri::HTML <<~HTML
        <html>
          <body>
            <div id="main">
              <ul>
                <li>
                  <span>
                    <a href="https://www.ecma-international.org/wp-content/uploads/ECMA-254_1st_edition_december_1996.pdf">Download</a>
                  </span>
                </li>
              </ul>
            </div>
          </body>
        </html>
      HTML

      source = subject.edition_source doc.at("//ul/li")

      expect(source).to be_instance_of Array
      expect(source.size).to eq 1
      expect(source.first).to be_instance_of Relaton::Bib::Uri
      expect(source.first.type).to eq "pdf"
      expect(source.first.content.to_s).to eq "https://www.ecma-international.org/wp-content/uploads/ECMA-254_1st_edition_december_1996.pdf"
    end
  end

  it "#parse_editions" do
    doc = Nokogiri::HTML <<~HTML
      <html>
        <body>
          <div id="main">
            <div>
              <div>
                <main>
                  <article>
                    <div>
                      <div>
                        <standard>
                          <div></div>
                          <div></div>
                          <div>
                            <ul>
                              <li>
                                <a href="https://262.ecma-international.org/5.1/index.html">ECMA-262 5.1 edition, June 2011</a>
                              </li>
                            </ul>
                          </div>
                        </standard>
                      </div>
                    </div>
                  </article>
                </main>
              </div>
            </div>
          </div>
        </body>
      </html>
    HTML
    translation_src = [
      { ed: "5.1", source: Relaton::Bib::Uri.new(type: "pdf", language: "ja", script: "Jpan", content: "https://example.com/ja.pdf") },
    ]
    parser = described_class.new(doc: doc, bib: bib, translation_source: translation_src)

    item = parser.parse.first
    expect(item).to be_instance_of Relaton::Ecma::ItemData
    expect(item.source).to be_instance_of Array
    expect(item.source.size).to eq 2
    expect(item.source.first).to be_instance_of Relaton::Bib::Uri
    expect(item.source.first.type).to eq "src"
    expect(item.source.first.content.to_s).to eq "https://262.ecma-international.org/5.1/index.html"
    expect(item.source.last).to be_instance_of Relaton::Bib::Uri
    expect(item.source.last.language).to eq "ja"
    expect(item.edition).to be_instance_of Relaton::Bib::Edition
    expect(item.edition.content).to eq "5.1"
    expect(item.date).to be_instance_of Array
    expect(item.date.size).to eq 1
    expect(item.date.first).to be_instance_of Relaton::Bib::Date
    expect(item.date.first.at.to_s).to eq "2011-06"
    expect(item.date.first.type).to eq "published"
  end

  it "#create_extent" do
    extent = subject.create_extent("1")
    expect(extent).to be_instance_of Array
    expect(extent.first).to be_instance_of Relaton::Bib::Extent
    expect(extent.first.locality.first.type).to eq "volume"
    expect(extent.first.locality.first.reference_from).to eq "1"
  end

  it "#create_extent returns nil for empty volume" do
    expect(subject.create_extent(nil)).to be_nil
    expect(subject.create_extent("")).to be_nil
  end
end
