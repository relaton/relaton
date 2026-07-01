require "relaton/oasis/data_fetcher"

describe Relaton::Oasis::DataPartParser do
  let(:node) do
    doc = Nokogiri::HTML <<-EOHTML
      <details>
        <summary>
          <div class="standard__preview">
            <h2>Some Standard v1.0</h2>
          </div>
        </summary>
        <div class="standard__details">
          <div class="standard__grid">
            <div class="standard__grid--cite-as">
              <p>
                <strong>[some-std-v1.0]</strong>
                <a href="http://example.com/doc.html">link</a>
              </p>
            </div>
          </div>
        </div>
      </details>
    EOHTML
    doc.at("//p")
  end

  subject { described_class.new(node) }

  context "#parse" do
    let(:node) do
      doc = Nokogiri::HTML <<-EOHTML
        <details>
          <summary>
            <div class="standard__preview">
              <h2>Some Standard v1.0</h2>
            </div>
          </summary>
          <div class="standard__details">
            <div class="standard__grid">
              <div class="standard__grid--cite-as">
                <p>
                  <strong>[some-std-v1.0]</strong>
                  <em>Test Doc Title</em>
                  Edited by John Doe. 15 March 2020.
                  <a href="http://example.com/doc.html">link</a>
                </p>
              </div>
            </div>
          </div>
        </details>
      EOHTML
      doc.at("//p")
    end

    before { allow(subject).to receive(:page).and_return(nil) }

    it "returns an ItemData with assembled attributes" do
      result = subject.parse
      expect(result).to be_a Relaton::Oasis::ItemData
      expect(result.type).to eq "standard"
      expect(result.title[0].content).to eq "Test Doc Title"
      expect(result.docidentifier[0].content).to eq "OASIS some-std-v1.0"
      expect(result.docidentifier[0].type).to eq "OASIS"
      expect(result.source[0].content).to eq "http://example.com/doc.html"
      expect(result.docnumber).to eq "some-std-v1.0"
      expect(result.date[0].at.to_s).to eq "2020-03-15"
      expect(result.date[0].type).to eq "issued"
      expect(result.language).to eq ["en"]
      expect(result.script).to eq ["Latn"]
      expect(result.relation[0].type).to eq "partOf"
      expect(result.ext.doctype.content).to eq "standard"
      expect(result.ext.flavor).to eq "oasis"
    end
  end

  context "errors guards" do # rubocop:disable Metrics/BlockLength
    let(:errors) { Hash.new(true) }
    let(:part_node) do
      doc = Nokogiri::HTML <<-EOHTML
        <details>
          <summary>
            <div class="standard__preview">
              <h2>Some Standard v1.0</h2>
            </div>
          </summary>
          <div class="standard__details">
            <div class="standard__grid">
              <div class="standard__grid--cite-as">
                <p>
                  <strong>[some-std-v1.0]</strong>
                  <em>Test Doc Title</em>
                  Edited by John Doe. 15 March 2020.
                  <a href="http://example.com/doc.html">link</a>
                </p>
              </div>
            </div>
          </div>
        </details>
      EOHTML
      doc.at("//p")
    end

    subject { described_class.new(part_node, errors) }

    before { allow(subject).to receive(:page).and_return(nil) }

    it "sets @errors[:part_title] to false on success" do
      subject.parse_title
      expect(errors[:part_title]).to be false
    end

    it "sets @errors[:part_date] to false on success" do
      subject.parse_date
      expect(errors[:part_date]).to be false
    end

    it "sets @errors[:part_docnumber] to false on success" do
      subject.parse_docnumber
      expect(errors[:part_docnumber]).to be false
    end

    it "sets @errors[:part_link] to false on success" do
      subject.parse_link
      expect(errors[:part_link]).to be false
    end

    it "keeps @errors[:part_abstract] true when page is nil" do
      subject.parse_abstract
      expect(errors[:part_abstract]).to be true
    end

    it "sets @errors[:part_editorialgroup_contributor] true when page is nil" do
      subject.parse_editorialgroup_contributor
      expect(errors[:part_editorialgroup_contributor]).to be true
    end

    it "sets @errors[:part_relation] to false on success" do
      subject.parse_relation
      expect(errors[:part_relation]).to be false
    end

    it "keeps @errors[:part_authorizer] true when page is nil" do
      subject.parse_authorizer
      expect(errors[:part_authorizer]).to be true
    end

    it "keeps @errors[:part_technology_area] true when no areas" do
      subject.parse_technology_area
      expect(errors[:part_technology_area]).to be true
    end
  end

  context "#parse_editorialgroup_contributor" do
    it "returns empty array when page is nil" do
      allow(subject).to receive(:page).and_return(nil)
      expect(subject.parse_editorialgroup_contributor).to eq []
    end

    it "returns empty array when no TCs on page" do
      page = Nokogiri::HTML <<-EOHTML
        <html><body>
          <p>Some unrelated content</p>
        </body></html>
      EOHTML
      allow(subject).to receive(:page).and_return(page)
      expect(subject.parse_editorialgroup_contributor).to eq []
    end

    it "returns contributor with subdivisions when TCs exist" do
      page = Nokogiri::HTML <<-EOHTML
        <html><body>
          <p>Technical Committee:</p>
          <p>
            <a href="https://example.com/tc1">OASIS Test TC</a>,
            <a href="https://example.com/tc2">OASIS Another TC</a>
          </p>
        </body></html>
      EOHTML
      allow(subject).to receive(:page).and_return(page)

      contrib = subject.parse_editorialgroup_contributor
      expect(contrib.size).to eq 1
      expect(contrib[0]).to be_a Relaton::Bib::Contributor
      expect(contrib[0].role[0].type).to eq "author"
      expect(contrib[0].role[0].description[0].content).to eq(
        "committee",
      )

      org = contrib[0].organization
      expect(org.name[0].content).to eq "OASIS"
      expect(org.subdivision.size).to eq 2
      expect(org.subdivision[0].type).to eq "technical-committee"
      expect(org.subdivision[0].name[0].content).to eq(
        "OASIS Test TC",
      )
      expect(org.subdivision[1].name[0].content).to eq(
        "OASIS Another TC",
      )
    end
  end

  context "#parse_abstract" do
    it "returns empty array when page is nil" do
      allow(subject).to receive(:page).and_return(nil)
      expect(subject.parse_abstract).to eq []
    end

    it "returns empty array when no abstract on page" do
      page = Nokogiri::HTML <<-EOHTML
        <html><body>
          <p>Some unrelated content</p>
        </body></html>
      EOHTML
      allow(subject).to receive(:page).and_return(page)
      expect(subject.parse_abstract).to eq []
    end

    it "returns abstract from page" do
      page = Nokogiri::HTML <<-EOHTML
        <html><body>
          <p>Abstract:</p>
          <p>This is the abstract\ntext.</p>
        </body></html>
      EOHTML
      allow(subject).to receive(:page).and_return(page)

      result = subject.parse_abstract
      expect(result.size).to eq 1
      expect(result[0]).to be_a Relaton::Bib::LocalizedMarkedUpString
      expect(result[0].content).to eq "This is the abstract text."
      expect(result[0].language).to eq "en"
      expect(result[0].script).to eq "Latn"
    end
  end

  context "#title" do
    let(:node) do
      doc = Nokogiri::HTML <<-EOHTML
        <details>
          <div class="standard__details">
            <div class="standard__grid">
              <div class="standard__grid--cite-as">
                <p>
                  <strong>[some-std-v1.0]</strong>
                  Some plain trailing text without markers
                  <a href="http://example.com/doc.html">link</a>
                </p>
              </div>
            </div>
          </div>
        </details>
      EOHTML
      doc.at("//p")
    end

    it "falls back to text when no title element and regex doesn't match" do
      expect { subject.title }.not_to raise_error
      expect(subject.title).to include "Some plain trailing text"
    end

    it "does not crash parse_docnumber on such nodes" do
      expect { subject.parse_docnumber }.not_to raise_error
    end
  end

  context "#parse_relation" do
    it "returns a partOf relation with parent docid" do
      rels = subject.parse_relation
      expect(rels.size).to eq 1
      expect(rels[0]).to be_a Relaton::Bib::Relation
      expect(rels[0].type).to eq "partOf"
      expect(rels[0].bibitem.formattedref.content).to eq "OASIS some-std-v1.0"
    end
  end

  context "#parse_authorizer" do
    it "returns empty array when page is nil" do
      allow(subject).to receive(:page).and_return(nil)
      expect(subject.parse_authorizer).to eq []
    end

    it "returns empty array when no TCs on page" do
      page = Nokogiri::HTML <<-EOHTML
        <html><body>
          <p>Some unrelated content</p>
        </body></html>
      EOHTML
      allow(subject).to receive(:page).and_return(page)
      expect(subject.parse_authorizer).to eq []
    end

    it "returns contributor per TC link" do
      page = Nokogiri::HTML <<-EOHTML
        <html><body>
          <p>Technical Committee:</p>
          <p>
            <a href="https://example.com/tc1">OASIS Test TC</a>,
            <a href="https://example.com/tc2">OASIS Another TC</a>
          </p>
        </body></html>
      EOHTML
      allow(subject).to receive(:page).and_return(page)

      contribs = subject.parse_authorizer
      expect(contribs.size).to eq 2

      expect(contribs[0]).to be_a Relaton::Bib::Contributor
      expect(contribs[0].organization.name[0].content).to eq "OASIS Test TC"
      expect(contribs[0].organization.uri[0].content).to eq(
        "https://example.com/tc1",
      )
      expect(contribs[0].role[0].type).to eq "authorizer"
      expect(contribs[0].role[0].description[0].content).to eq "Committee"

      expect(contribs[1].organization.name[0].content).to eq(
        "OASIS Another TC",
      )
      expect(contribs[1].organization.uri[0].content).to eq(
        "https://example.com/tc2",
      )
      expect(contribs[1].role[0].type).to eq "authorizer"
      expect(contribs[1].role[0].description[0].content).to eq "Committee"
    end
  end
end
