# frozen_string_literal: true

RSpec.describe Relaton::Adobe::Bibliography do
  let(:yaml) do
    {
      "id" => "ATN5014",
      "type" => "standard",
      "docidentifier" => [{ "content" => "Adobe TN 5014", "type" => "ADOBE", "primary" => true }],
      "title" => [{ "content" => "Adobe CMap and CID Font Files Specification", "language" => "eng", "type" => "main" }],
      "ext" => { "doctype" => { "content" => "tech-note" }, "flavor" => "adobe", "tech_note_number" => "5014" },
    }.to_yaml
  end

  # Stub the private index so no remote zip is fetched; webmock serves the record.
  def stub_index(rows)
    allow(described_class).to receive(:index)
      .and_return(instance_double(Relaton::Index::Type, search: rows))
  end

  it "fetches and deserializes a matching record" do
    stub_index([{ id: "ATN5014", file: "data/5014.yaml" }])
    stub_request(:get, "#{described_class::ENDPOINT}data/5014.yaml")
      .to_return(status: 200, body: yaml)

    item = described_class.get("Adobe TN 5014")
    expect(item).to be_a(Relaton::Adobe::ItemData)
    expect(item.docidentifier.first.content).to eq "Adobe TN 5014"
    expect(item.ext.tech_note_number).to eq "5014"
    expect(item.fetched).to eq Date.today.to_s
  end

  it "returns nil and logs when the index has no match" do
    stub_index([])
    expect { expect(described_class.get("Adobe TN 9999")).to be_nil }
      .to output(/\[relaton-adobe\] INFO: \(Adobe TN 9999\) Not found\./)
      .to_stderr_from_any_process
  end

  it "raises RequestError on a non-200 response" do
    stub_index([{ id: "ATN5014", file: "data/5014.yaml" }])
    stub_request(:get, "#{described_class::ENDPOINT}data/5014.yaml")
      .to_return(status: 404, body: "Not Found")

    expect { described_class.get("Adobe TN 5014") }
      .to raise_error(Relaton::RequestError)
  end
end
