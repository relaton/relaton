require "jing"

RSpec.describe Relaton::Gost::Bibdata do
  subject(:bibdata) do
    described_class.from_hash(
      "id" => "GOST R 34.12-2015",
      "type" => "standard",
      "title" => [{
        "language" => "eng", "type" => "main", "format" => "text/plain",
        "content" => "Information technology — Cryptographic data security — Block cipher"
      }],
      "docidentifier" => [{
        "content" => "GOST R 34.12-2015", "type" => "GOST", "primary" => true
      }],
      "date" => [{ "type" => "published", "on" => "2015" }],
      "ext" => {
        "doctype" => { "content" => "national" },
        "flavor" => "gost",
        "urn" => "urn:gost:std:r:34.12:2015",
        "webpage" => "https://www.gost.ru/portal/gost",
        "ics_code" => "35.030",
        "developer" => "ТК 26",
        "keywords" => %w[cipher block],
        "pages" => "20",
        "designation_original" => "ГОСТ Р 34.12— 2015",
      },
    )
  end

  it "produces XML that validates against the GOST RelaxNG schema" do
    file = "fixtures/gost_bibdata.xml"
    xml = bibdata.to_xml bibdata: true
    File.write file, xml, encoding: "UTF-8" unless File.exist? file

    schema = Jing.new "../../grammar/relaton-gost-compile.rng"
    errors = schema.validate file
    expect(errors).to eq []
  end

  it "round-trips the GOST-specific ext elements through XML" do
    restored = described_class.from_xml bibdata.to_xml(bibdata: true)
    expect(restored.ext.urn).to eq "urn:gost:std:r:34.12:2015"
    expect(restored.ext.ics_code).to eq "35.030"
    expect(restored.ext.keywords).to eq %w[cipher block]
    expect(restored.ext.designation_original).to eq "ГОСТ Р 34.12— 2015"
    expect(restored.ext.doctype.content).to eq "national"
  end
end
