require "relaton/oasis/data_fetcher"

describe Relaton::Oasis::DataParser do # rubocop:disable Metrics/BlockLength
  let(:node) do
    Nokogiri::HTML File.read(
      "fixtures/amqp-v10.html", encoding: "UTF-8"
    )
  end

  let(:mqtt_v50) do
    html = File.read("fixtures/mqtt-v50.html", encoding: "UTF-8")
    Nokogiri::HTML(html).at("//details")
  end

  let(:csaf_v20) do
    html = File.read("fixtures/csaf-v20.html", encoding: "UTF-8")
    Nokogiri::HTML(html).at("//details")
  end

  subject { described_class.new(node.at("//details")) }

  it "parse", vcr: "amqp-v10" do
    bib = subject.parse
    xml = bib.to_xml bibdata: true
    file = "fixtures/oasis_bibdata.xml"
    File.write file, xml, encoding: "UTF-8" unless File.exist? file
    expect(bib).to be_a Relaton::Oasis::ItemData
    expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8")
      .gsub(
        /(?<=<fetched>)\d{4}-\d{2}-\d{2}(?=<\/fetched>)/,
        Date.today.to_s,
      )
  end

  it "parses title" do
    title = subject.parse_title
    expect(title).to be_a Array
    expect(title[0]).to be_a Relaton::Bib::Title
    expect(title[0].type).to eq "main"
    expect(title[0].content).to eq(
      "Advanced Message Queueing Protocol (AMQP) v1.0",
    )
  end

  context "parses docid" do # rubocop:disable Metrics/BlockLength
    context "from parts" do # rubocop:disable Metrics/BlockLength
      it "when there is only one part" do
        doc = Nokogiri::HTML <<-EOHTML
          <details>
            <summary>
              <div class="standard__preview">
                <h2>Advanced Message Queueing Protocol (AMQP) v1.0</h2>
              </div>
            </summary>
            <div class="standard__details">
              <div class="standard__grid">
                <div class="standard__grid--cite-as">
                  <p><strong>[amqp-core-overview-v1.0]</strong></p>
                </div>
              </div>
            </div>
          </details>
        EOHTML
        parser = described_class.new doc.at("//details")
        docid = parser.parse_docid
        expect(docid).to be_a Array
        expect(docid[0]).to be_a Relaton::Bib::Docidentifier
        expect(docid[0].content).to eq(
          "OASIS amqp-core-overview-v1.0",
        )
        expect(docid[0].primary).to be true
      end

      it "OASIS Committee Specification" do
        doc = Nokogiri::HTML <<-EOHTML
          <details>
            <summary>
              <div class="standard__preview">
                <h2>Advanced Message Queuing Protocol (AMQP) Enforcing Connection Uniqueness Version 1.0</h2>
              </div>
            </summary>
            <div class="standard__details">
              <div class="standard__grid">
                <div class="standard__grid--cite-as">
                  <p>
                    <strong>[soleconn-v1.0]</strong>
                    <em>17 September 2018. OASIS Committee Specification 01. Latest version: </em>
                  </p>
                </div>
              </div>
            </div>
          </details>
        EOHTML
        parser = described_class.new doc.at("//details")
        docid = parser.parse_docid
        expect(docid[0].content).to eq(
          "OASIS soleconn-v1.0-CS01",
        )
      end

      it "OASIS Project Specification" do
        doc = Nokogiri::HTML <<-EOHTML
          <details>
            <summary>
              <div class="standard__preview">
                <h2>OSLC Architecture Management Version 3.0 Project Specification 01</h2>
              </div>
            </summary>
            <div class="standard__details">
              <div class="standard__grid">
                <div class="standard__grid--cite-as">
                  <p>
                    <strong>[OSLC-AM-3.0-Part1]</strong>
                    <em>30 September 2021. OASIS Project Specification 01. Latest version: </em>
                  </p>
                </div>
              </div>
            </div>
          </details>
        EOHTML
        parser = described_class.new doc.at("//details")
        docid = parser.parse_docid
        expect(docid[0].content).to eq(
          "OASIS OSLC-AM-3.0-Part1-PS01",
        )
      end

      it "when there are multiple parts" do
        doc = Nokogiri::HTML <<-EOHTML
          <details>
            <summary>
              <div class="standard__preview">
                <h2>Advanced Message Queueing Protocol (AMQP) v1.0</h2>
              </div>
            </summary>
            <div class="standard__details">
              <div class="standard__grid">
                <div class="standard__grid--cite-as">
                  <p><strong>[amqp-core-overview-v1.0]</strong></p>
                  <p><strong>[amqp-core-types-v1.0]</strong></p>
                </div>
              </div>
            </div>
          </details>
        EOHTML
        parser = described_class.new doc.at("//details")
        docid = parser.parse_docid
        expect(docid[0].content).to eq "OASIS amqp-core"
      end

      context "from title" do
        it "with abbreviations in parentheses" do
          doc = Nokogiri::HTML <<-EOHTML
            <details>
              <summary>
                <div class="standard__peview">
                  <h2>Emergency Data Exchange Language (EDXL) Hospital AVailability Exchange (HAVE) Version 2.0</h2>
                </div>
              </summary>
            </details>
          EOHTML
          parser = described_class.new doc.at("//details")
          dociid = parser.parse_docid
          expect(dociid[0].content).to eq(
            "OASIS EDXL-HAVE-v2.0",
          )
        end

        it "with abbreviations in text" do
          doc = Nokogiri::HTML <<-EOHTML
            <details>
              <summary>
                <div class="standard__peview">
                  <h2>Emergency Data Exchange Language EDXL Hospital AVailability Exchange HAVE Version 2.0</h2>
                </div>
              </summary>
            </details>
          EOHTML
          parser = described_class.new doc.at("//details")
          dociid = parser.parse_docid
          expect(dociid[0].content).to eq(
            "OASIS EDXL-HAVE-v2.0",
          )
        end

        it "without abbreviations" do
          doc = Nokogiri::HTML <<-EOHTML
            <details>
              <summary>
                <div class="standard__preview">
                  <h2>ebXML Message Service Specification v2.0 [OASIS 200204]</h2>
                </div>
              </summary>
            </details>
          EOHTML
          parser = described_class.new doc.at("//details")
          dociid = parser.parse_docid
          expect(dociid[0].content).to eq(
            "OASIS ebXML-MSS-v2.0",
          )
        end
      end

      it "csaf-v20" do
        parser = described_class.new csaf_v20
        docid = parser.parse_docid
        expect(docid[0].content).to eq "OASIS csaf-v2.0-CS02"
      end
    end
  end

  it "parses date" do
    date = subject.parse_date
    expect(date).to be_a Array
    expect(date[0]).to be_a Relaton::Bib::Date
    expect(date[0].at.to_s).to eq "2012-10-30"
    expect(date[0].type).to eq "issued"
  end

  it "parses abstract" do
    abstract = subject.parse_abstract
    expect(abstract).to be_a Array
    expect(abstract[0]).to be_a(
      Relaton::Bib::LocalizedMarkedUpString,
    )
    expect(abstract[0].content).to eq(
      "An open internet protocol for business messaging.",
    )
    expect(abstract[0].language).to eq "en"
    expect(abstract[0].script).to eq "Latn"
  end

  context "parses editorialgroup contributor" do
    it "returns empty array when no TCs" do
      doc = Nokogiri::HTML <<-EOHTML
        <details>
          <summary>
            <div class="standard__preview">
              <h2>Some Standard v1.0</h2>
            </div>
          </summary>
          <div class="standard__details">
            <p>No links here</p>
          </div>
        </details>
      EOHTML
      parser = described_class.new doc.at("//details")
      expect(parser.parse_editorialgroup_contributor).to eq []
    end

    it "with single TC" do
      contrib = subject.parse_editorialgroup_contributor
      expect(contrib).to be_a Array
      expect(contrib.size).to eq 1
      expect(contrib[0]).to be_a Relaton::Bib::Contributor
      expect(contrib[0].role).to be_a Array
      expect(contrib[0].role[0].type).to eq "author"
      expect(contrib[0].role[0].description[0].content).to eq(
        "committee",
      )
      org = contrib[0].organization
      expect(org).to be_a Relaton::Bib::Organization
      expect(org.name[0].content).to eq "OASIS"
      expect(org.subdivision).to be_a Array
      expect(org.subdivision[0]).to be_a(
        Relaton::Bib::Subdivision,
      )
      expect(org.subdivision[0].type).to eq(
        "technical-committee",
      )
      expect(org.subdivision[0].name[0].content).to eq(
        "OASIS Advanced Message Queuing Protocol (AMQP) TC",
      )
    end

    it "with multiple TCs" do
      doc = Nokogiri::HTML <<-EOHTML
        <details>
          <summary>
            <div class="standard__preview">
              <h2>Some Standard v1.0</h2>
            </div>
          </summary>
          <div class="standard__details">
            <a href="https://example.com/tc1">OASIS First TC</a>
            <a href="https://example.com/tc2">OASIS Second TC</a>
          </div>
        </details>
      EOHTML
      parser = described_class.new doc.at("//details")
      contrib = parser.parse_editorialgroup_contributor
      expect(contrib.size).to eq 1
      org = contrib[0].organization
      expect(org.name[0].content).to eq "OASIS"
      expect(org.subdivision.size).to eq 2
      expect(org.subdivision[0].name[0].content).to eq(
        "OASIS First TC",
      )
      expect(org.subdivision[1].name[0].content).to eq(
        "OASIS Second TC",
      )
    end
  end

  it "parses relation" do
    rel = subject.parse_relation
    expect(rel).to be_a Array
  end

  it "parses link" do
    dp = described_class.new mqtt_v50
    link = dp.parse_link
    expect(link).to be_a Array
    expect(link.size).to eq 3
    expect(link[0]).to be_a Relaton::Bib::Uri
    expect(link[0].content).to eq(
      "http://docs.oasis-open.org/mqtt/mqtt/v5.0/os/" \
      "mqtt-v5.0-os.html",
    )
    expect(link[0].type).to eq "src"
    expect(link[1]).to be_a Relaton::Bib::Uri
    expect(link[1].content).to eq(
      "http://docs.oasis-open.org/mqtt/mqtt/v5.0/os/" \
      "mqtt-v5.0-os.pdf",
    )
    expect(link[1].type).to eq "pdf"
    expect(link[2]).to be_a Relaton::Bib::Uri
    expect(link[2].content).to eq(
      "http://docs.oasis-open.org/mqtt/mqtt/v5.0/os/" \
      "mqtt-v5.0-os.docx",
    )
    expect(link[2].type).to eq "doc"
  end

  it "parses document with multiple parts",
     vcr: "odata-json-format-40" do
    doc = Nokogiri::HTML File.read(
      "fixtures/odata-json-format-40.html",
      encoding: "UTF-8",
    )
    dp = described_class.new doc.at("//details")
    bib = dp.parse
    expect(bib.docidentifier[0].content).to eq(
      "OASIS OData-JSON-Format-v4.0",
    )
  end

  it "#parse_contributor", vcr: "mqtt-v50" do
    dp = described_class.new mqtt_v50
    expect(dp).to receive(:publisher_oasis)
      .and_return([:oasis])
    expect(dp).to receive(:parse_authorizer)
      .and_return([:publisher])
    expect(dp).to receive(:parse_editorialgroup_contributor)
      .and_return([:editorialgroup])
    expect(dp).to receive(:parse_chairs)
      .and_return([:chairs])
    expect(dp).to receive(:parse_editors)
      .and_return([:editors])
    expect(dp.parse_contributor).to eq(
      %i[oasis publisher editorialgroup chairs editors],
    )
  end

  it "#publisher_oasis" do
    dp = described_class.new mqtt_v50
    contrib = dp.publisher_oasis
    expect(contrib).to be_a Array
    expect(contrib.size).to eq 1
    expect(contrib[0]).to be_a Relaton::Bib::Contributor
    expect(contrib[0].role).to be_a Array
    expect(contrib[0].role.size).to eq 2
    expect(contrib[0].role[0].type).to eq "authorizer"
    expect(contrib[0].role[0].description).to be_instance_of(
      Array,
    )
    expect(contrib[0].role[0].description.size).to eq 1
    expect(contrib[0].role[0].description[0].content).to eq(
      "Standards Development Organization",
    )
    expect(contrib[0].role[1].type).to eq "publisher"
    org = contrib[0].organization
    expect(org).to be_a Relaton::Bib::Organization
    expect(org.name).to be_a Array
    expect(org.name.size).to eq 1
    expect(org.name[0].content).to eq "OASIS"
    expect(org.uri).to be_a Array
    expect(org.uri.size).to eq 1
    expect(org.uri[0]).to be_a Relaton::Bib::Uri
    expect(org.uri[0].type).to eq "uri"
    expect(org.uri[0].content).to eq(
      "https://www.oasis-open.org/",
    )
  end

  it "#parse_authorizer", vcr: "mqtt-v50" do
    dp = described_class.new mqtt_v50
    contrib = dp.parse_authorizer
    expect(contrib).to be_a Array
    expect(contrib.size).to eq 1
    expect(contrib[0]).to be_a Relaton::Bib::Contributor
    expect(contrib[0].role).to be_a Array
    expect(contrib[0].role.size).to eq 1
    expect(contrib[0].role[0].type).to eq "authorizer"
    expect(contrib[0].role[0].description).to be_instance_of(
      Array,
    )
    expect(contrib[0].role[0].description.size).to eq 1
    expect(contrib[0].role[0].description[0].content).to eq(
      "Committee",
    )
    org = contrib[0].organization
    expect(org).to be_a Relaton::Bib::Organization
    expect(org.name).to be_a Array
    expect(org.name.size).to eq 1
    expect(org.name[0].content).to eq(
      "OASIS Message Queuing Telemetry Transport (MQTT) TC",
    )
    expect(org.uri).to be_a Array
    expect(org.uri.size).to eq 1
    expect(org.uri[0]).to be_a Relaton::Bib::Uri
    expect(org.uri[0].type).to eq "uri"
    expect(org.uri[0].content).to eq(
      "https://www.oasis-open.org/committees/mqtt/",
    )
  end

  it "#parses_chairs", vcr: "mqtt-v50" do # rubocop:disable Metrics/ExampleLength
    dp = described_class.new mqtt_v50
    contrib = dp.parse_chairs
    expect(contrib).to be_a Array
    expect(contrib.size).to eq 1
    c = contrib[0]
    expect(c).to be_a Relaton::Bib::Contributor
    expect(c.role).to be_a Array
    expect(c.role.size).to eq 1
    expect(c.role[0].type).to eq "editor"
    expect(c.role[0].description).to be_instance_of Array
    expect(c.role[0].description.size).to eq 1
    expect(c.role[0].description[0].content).to eq "Chair"
    person = c.person
    expect(person).to be_a Relaton::Bib::Person
    expect(person.name).to be_a Relaton::Bib::FullName
    expect(person.name.forename).to be_a Array
    expect(person.name.forename.size).to eq 1
    expect(person.name.forename[0]).to be_a(
      Relaton::Bib::FullNameType::Forename,
    )
    expect(person.name.forename[0].content).to eq "Richard"
    expect(person.name.surname).to be_a(
      Relaton::Bib::LocalizedString,
    )
    expect(person.name.surname.content).to eq "Coppen"
    expect(person.email).to be_a Array
    expect(person.email.size).to eq 1
    expect(person.email[0]).to eq "coppen@uk.ibm.com"
    expect(person.affiliation).to be_a Array
    expect(person.affiliation.size).to eq 1
    aff = person.affiliation[0]
    expect(aff).to be_a Relaton::Bib::Affiliation
    expect(aff.organization).to be_a(
      Relaton::Bib::Organization,
    )
    expect(aff.organization.name).to be_a Array
    expect(aff.organization.name.size).to eq 1
    expect(aff.organization.name[0].content).to eq "IBM"
    expect(aff.organization.uri).to be_a Array
    expect(aff.organization.uri.size).to eq 1
    expect(aff.organization.uri[0]).to be_a Relaton::Bib::Uri
    expect(aff.organization.uri[0].type).to eq "uri"
    expect(aff.organization.uri[0].content).to eq(
      "http://www.ibm.com",
    )
  end

  it "parses editors", vcr: "mqtt-v50" do # rubocop:disable Metrics/ExampleLength
    dp = described_class.new mqtt_v50
    contrib = dp.parse_editors
    expect(contrib).to be_a Array
    expect(contrib.size).to eq 4
    c = contrib[0]
    expect(c).to be_a Relaton::Bib::Contributor
    expect(c.role.size).to eq 1
    expect(c.role[0].type).to eq "editor"
    person = c.person
    expect(person).to be_a Relaton::Bib::Person
    expect(person.name).to be_a Relaton::Bib::FullName
    expect(person.name.forename).to be_a Array
    expect(person.name.forename.size).to eq 1
    expect(person.name.forename[0]).to be_a(
      Relaton::Bib::FullNameType::Forename,
    )
    expect(person.name.forename[0].content).to eq "Andrew"
    expect(person.name.surname).to be_a(
      Relaton::Bib::LocalizedString,
    )
    expect(person.name.surname.content).to eq "Banks"
    expect(person.email).to be_a Array
    expect(person.email.size).to eq 1
    expect(person.email[0]).to eq "andrew_banks@uk.ibm.com"
    expect(person.affiliation).to be_a Array
    expect(person.affiliation.size).to eq 1
    aff = person.affiliation[0]
    expect(aff).to be_a Relaton::Bib::Affiliation
    expect(aff.organization).to be_a(
      Relaton::Bib::Organization,
    )
    expect(aff.organization.name).to be_a Array
    expect(aff.organization.name.size).to eq 1
    expect(aff.organization.name[0].content).to eq "IBM"
    expect(aff.organization.uri).to be_a Array
    expect(aff.organization.uri.size).to eq 1
    expect(aff.organization.uri[0]).to be_a Relaton::Bib::Uri
    expect(aff.organization.uri[0].type).to eq "uri"
    expect(aff.organization.uri[0].content).to eq(
      "http://www.ibm.com",
    )
    expect(contrib[1].person.name.forename[0].content).to eq(
      "Ed",
    )
    expect(contrib[1].person.name.surname.content).to eq(
      "Briggs",
    )
    expect(contrib[2].person.name.forename[0].content).to eq(
      "Ken",
    )
    expect(contrib[2].person.name.surname.content).to eq(
      "Borgendale",
    )
    expect(contrib[3].person.name.forename[0].content).to eq(
      "Rahul",
    )
    expect(contrib[3].person.name.surname.content).to eq(
      "Gupta",
    )
  end

  context "errors guards" do # rubocop:disable Metrics/BlockLength
    let(:errors) { Hash.new(true) }

    it "sets @errors[:title] to false on success" do
      parser = described_class.new(node.at("//details"), errors)
      parser.parse_title
      expect(errors[:title]).to be false
    end

    it "sets @errors[:date] to false on success" do
      parser = described_class.new(node.at("//details"), errors)
      parser.parse_date
      expect(errors[:date]).to be false
    end

    it "sets @errors[:abstract] to false on success" do
      parser = described_class.new(node.at("//details"), errors)
      parser.parse_abstract
      expect(errors[:abstract]).to be false
    end

    it "sets @errors[:editorialgroup_contributor] to false on success" do
      parser = described_class.new(node.at("//details"), errors)
      parser.parse_editorialgroup_contributor
      expect(errors[:editorialgroup_contributor]).to be false
    end

    it "sets @errors[:authorizer] to false on success" do
      parser = described_class.new(node.at("//details"), errors)
      parser.parse_authorizer
      expect(errors[:authorizer]).to be false
    end

    it "sets @errors[:relation] to false on success" do
      parser = described_class.new(node.at("//details"), errors)
      parser.parse_relation
      expect(errors[:relation]).to be false
    end

    it "sets @errors[:link] to false on success" do
      parser = described_class.new(mqtt_v50, errors)
      parser.parse_link
      expect(errors[:link]).to be false
    end

    it "sets @errors[:docnumber] to false on success" do
      parser = described_class.new(node.at("//details"), errors)
      parser.parse_docnumber
      expect(errors[:docnumber]).to be false
    end

    it "sets @errors[:technology_area] to false on success" do
      parser = described_class.new(node.at("//details"), errors)
      parser.parse_technology_area
      expect(errors[:technology_area]).to be false
    end
  end

  it "get editors from node if there is no link" do
    doc = Nokogiri::HTML File.read(
      "fixtures/ciq-v10.html", encoding: "UTF-8"
    )
    dp = described_class.new doc.at("//details")
    editors = dp.parse_editors
    expect(editors).to be_a Array
    expect(editors.size).to eq 1
    expect(editors[0]).to be_a Relaton::Bib::Contributor
    expect(editors[0].role).to be_a Array
    expect(editors[0].role.size).to eq 1
    expect(editors[0].role[0].type).to eq "editor"
    expect(editors[0].person).to be_a Relaton::Bib::Person
    expect(editors[0].person.name).to be_a(
      Relaton::Bib::FullName,
    )
    expect(editors[0].person.name.forename).to be_a Array
    expect(editors[0].person.name.forename.size).to eq 1
    expect(editors[0].person.name.forename[0]).to be_a(
      Relaton::Bib::FullNameType::Forename,
    )
    expect(editors[0].person.name.forename[0].content).to eq(
      "Ram",
    )
    expect(editors[0].person.name.surname).to be_a(
      Relaton::Bib::LocalizedString,
    )
    expect(editors[0].person.name.surname.content).to eq(
      "Kumar",
    )
  end
end
