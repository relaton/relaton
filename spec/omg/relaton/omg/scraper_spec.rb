# frozen_string_literal: true

RSpec.describe Relaton::Omg::Scraper do
  # The OMG server renders the month name in its own locale, and the CDN caches
  # that variant. The JSON-LD block keeps the date machine-readable.
  it "reads the date from JSON-LD when the page shows a localized month" do
    scraper = described_class.new "UML", "2.1.1"
    doc = Nokogiri::HTML File.read("fixtures/localized_date.html", encoding: "UTF-8")
    scraper.instance_variable_set :@doc, doc
    expect(scraper.pub_date.to_s).to eq "2007-07-31"
  end

  it "falls back to the visible date when the page has no JSON-LD" do
    scraper = described_class.new "UML", "2.1.1"
    doc = Nokogiri::HTML '<dl><dt>Publication Date:</dt><dd>July 2007</dd></dl>'
    scraper.instance_variable_set :@doc, doc
    expect(scraper.pub_date.to_s).to eq "2007-07-01"
  end

  it "returns no date when the visible date is not parsable" do
    scraper = described_class.new "UML", "2.1.1"
    doc = Nokogiri::HTML '<dl><dt>Publication Date:</dt><dd>七月 2007</dd></dl>'
    scraper.instance_variable_set :@doc, doc
    expect { expect(scraper.pub_date).to be_nil }
      .to output(/Cannot parse the publication date/).to_stderr_from_any_process
  end
end
