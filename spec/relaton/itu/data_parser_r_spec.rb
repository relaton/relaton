require "relaton/itu/data_parser_r"

describe Relaton::Itu::DataParserR do
  it "parse" do
    doc = Nokogiri::HTML <<~HTML
      <html><body>
        <div id="idDocSetPropertiesWebPart">
          <h2>R-REC-1234-5-2020</h2>
        </div>
        <table>
          <tr><td><h3>Title</h3></td><td></td><td>Test title</td></tr>
          <tr><td><h3>Observation</h3></td><td></td><td>Test abstract</td></tr>
          <tr><td><h3>Approval_Date</h3></td><td></td><td>2019-01-01</td></tr>
          <tr><td><h3>Version year</h3></td><td></td><td>2019</td></tr>
          <tr><td><h3>Status</h3></td><td></td><td>In force</td></tr>
        </table>
      </body></html>
    HTML
    url = "https://www.itu.int/rec/R-REC-1234-5-2020"
    result = described_class.parse(doc, url, "recommendation")
    expect(result).to be_instance_of Relaton::Itu::ItemData
    expect(result.docidentifier.first.content).to eq "ITU-R 1234-5"
    expect(result.title.first.content).to eq "Test title"
    expect(result.abstract.first.content).to eq "Test abstract"
    expect(result.date.size).to eq 3
    expect(result.language).to eq ["en"]
    expect(result.script).to eq ["Latn"]
    expect(result.source.first.content.to_s).to eq url
    expect(result.status.stage.content).to eq "In force"
    expect(result.type).to eq "standard"
    expect(result.ext.doctype.type).to eq "recommendation"
  end

  it "fetch_docid" do
    doc = Nokogiri::HTML <<~HTML
      <html>
        <body>
          <div id="idDocSetPropertiesWebPart">
            <h2>R-REC-1234-5</h2>
          </div>
        </body>
      </html>
    HTML
    docid = described_class.fetch_docid doc
    expect(docid).to be_instance_of Array
    expect(docid.size).to eq 1
    expect(docid.first).to be_instance_of Relaton::Bib::Docidentifier
    expect(docid.first.type).to eq "ITU"
    expect(docid.first.content).to eq "ITU-R 1234-5"
    expect(docid.first.primary).to be true
  end

  it "fetch_title" do
    doc = Nokogiri::HTML <<~HTML
      <html>
        <body>
          <table>
            <tr>
              <td><h3>Title</h3></td>
              <td></td>
              <td>title</td>
            </tr>
          </table>
        </body>
      </html>
    HTML
    title = described_class.fetch_title doc
    expect(title).to be_instance_of Array
    expect(title.size).to eq 1
    expect(title.first).to be_instance_of Relaton::Bib::Title
    expect(title.first.type).to eq "main"
    expect(title.first.content).to eq "title"
    expect(title.first.language).to eq "en"
    expect(title.first.script).to eq "Latn"
  end

  it "fetch_abstract" do
    doc = Nokogiri::HTML <<~HTML
      <html>
        <body>
          <table>
            <tr>
              <td><h3>Observation</h3></td>
              <td></td>
              <td>abstract</td>
            </tr>
          </table>
        </body>
      </html>
    HTML
    abstract = described_class.fetch_abstract doc
    expect(abstract).to be_instance_of Array
    expect(abstract.size).to eq 1
    expect(abstract.first).to be_instance_of Relaton::Bib::LocalizedMarkedUpString
    expect(abstract.first.content).to eq "abstract"
    expect(abstract.first.language).to eq "en"
    expect(abstract.first.script).to eq "Latn"
  end

  it "fetch_date" do
    doc = Nokogiri::HTML <<~HTML
      <html>
        <body>
          <table>
            <tr>
              <td><h3>Approval_Date</h3></td>
              <td></td>
              <td>2019-01-01</td>
            </tr>
            <tr>
              <td><h3>Version year</h3></td>
              <td></td>
              <td>2019</td>
            </tr>
          </table>
          <div id="idDocSetPropertiesWebPart">
            <h2>R-REC-1234-5-2020</h2>
          </div>
        </body>
      </html>
    HTML
    date = described_class.fetch_date doc
    expect(date).to be_instance_of Array
    expect(date.size).to eq 3
    expect(date.first).to be_instance_of Relaton::Bib::Date
    expect(date.first.type).to eq "confirmed"
    expect(date.first.at.to_s).to eq "2019-01-01"
    expect(date[1].type).to eq "updated"
    expect(date[1].at.to_s).to eq "2019"
    expect(date.last.type).to eq "published"
    expect(date.last.at.to_s).to eq "2020"
  end

  context "parse_date" do
    it "year-month" do
      date = described_class.parse_date "201901", "confirmed"
      expect(date).to be_instance_of Relaton::Bib::Date
      expect(date.type).to eq "confirmed"
      expect(date.at.to_s).to eq "2019-01"
    end

    it "year-month-day" do
      date = described_class.parse_date "1/22/2019", "confirmed"
      expect(date.at.to_s).to eq "2019-01-22"
    end
  end

  it "fetch_source" do
    source = described_class.fetch_source "https://www.itu.int"
    expect(source).to be_instance_of Array
    expect(source.size).to eq 1
    expect(source.first).to be_instance_of Relaton::Bib::Uri
    expect(source.first.type).to eq "src"
    expect(source.first.content.to_s).to eq "https://www.itu.int"
  end

  context "fetch_status" do
    it do
      doc = Nokogiri::HTML <<~HTML
        <html>
          <body>
            <table>
              <tr>
                <td><h3>Status</h3></td>
                <td></td>
                <td>In force</td>
              </tr>
            </table>
          </body>
        </html>
      HTML
      status = described_class.fetch_status doc
      expect(status).to be_instance_of Relaton::Bib::Status
      expect(status.stage.content).to eq "In force"
    end
  end

  it "fetch_doctype" do
    doctype = described_class.fetch_doctype "technical-report"
    expect(doctype).to be_instance_of Relaton::Itu::Doctype
    expect(doctype.type).to eq "technical-report"
  end
end
