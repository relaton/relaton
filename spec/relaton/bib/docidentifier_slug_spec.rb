# frozen_string_literal: true

require "spec_helper"

# The slug form (relaton#441): Docidentifier#to_s(form: :slug) renders
# the pubid-scheme URN in HTTP-path clothes; Pubid.from_slug parses it
# back to the same identifier. Flavors whose pubid-scheme schema has
# not landed yet degrade to the stored content.
RSpec.describe Relaton::Bib::Docidentifier do
  it "renders and parses the slug for a landed flavor" do
    require "pubid"
    docid = described_class.new(type: "NIST", content: "NIST SP 800-53r5")

    slug = docid.to_s(form: :slug)
    expect(slug).to eq("nist/sp/800-53/pub-NIST/series-SP/subseries-800/edtype-r/ed-5")

    back = ::Pubid.from_slug(slug)
    expect(back.to_hash).to eq(::Pubid::Nist.parse("NIST SP 800-53r5").to_hash)
  end

  it "keeps to_s without a form on the stored content" do
    docid = described_class.new(type: "NIST", content: "NIST SP 800-53r5")
    expect(docid.to_s).to eq("NIST SP 800-53r5")
  end

  it "raises on an unknown form" do
    docid = described_class.new(type: "NIST", content: "NIST SP 800-53r5")
    expect { docid.to_s(form: :nonsense) }.to raise_error(ArgumentError)
  end

  it "degrades to content for a flavor without a landed schema" do
    docid = described_class.new(type: "CSA", content: "CSA C22.2 NO. 125-M84 (R2004)")
    expect(docid.to_s(form: :slug)).to eq("CSA C22.2 NO. 125-M84 (R2004)")
  end
end
