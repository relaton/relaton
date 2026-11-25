# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "relaton" # Relaton::Db::Registry, for the routing check

# The PDF Association acceptance list (relaton#601, relaton-data-adobe#9,
# metanorma-pdfa#114): every Adobe document the PDF Association cites, as the
# canonical reference a citing document writes. Each one must route to the
# Adobe flavor and resolve to its own record in the published index.
#
# The index is `spec/adobe/fixtures/index-v2.yaml`, the live
# relaton-data-adobe `index-v2.yaml` copied wholesale (52 rows, 2026-11-24; unchanged on 2026-11-25).
# It is read through `Relaton::Index::Type` with the runtime `pubid_class:`,
# so a row's `:id` is a `Pubid::Adobe` identifier, as at runtime. The record
# fetch is stubbed: the example asserts the file the lookup asks for.
RSpec.describe "Adobe PDF Association citation corpus" do
  # reference => the data file its record lives in
  cited_tech_notes = {
    "Adobe TN 5001" => "atn5001", "Adobe TN 5014" => "atn5014",
    "Adobe TN 5015" => "atn5015", "Adobe TN 5044" => "atn5044",
    "Adobe TN 5088" => "atn5088", "Adobe TN 5092" => "atn5092",
    "Adobe TN 5094" => "atn5094", "Adobe TN 5116" => "atn5116",
    "Adobe TN 5176" => "atn5176", "Adobe TN 5177" => "atn5177",
    "Adobe TN 5411" => "atn5411", "Adobe TN 5620" => "atn5620",
    "Adobe TN 5660" => "atn5660", "Adobe TN 5902" => "atn5902"
  }.freeze

  # The 17 Adobe documents ISO 32000-2 cites (relaton-data-adobe#9), minus
  # PDF 1.1, which has no record (see pending).
  cited_publications = {
    "Adobe Publication pdf-reference-1.0" => "pdf-reference-1.0",
    "Adobe Publication pdf-reference-1.2" => "pdf-reference-1.2",
    "Adobe Publication pdf-reference-1.3" => "pdf-reference-1.3",
    "Adobe Publication pdf-reference-1.4" => "pdf-reference-1.4",
    "Adobe Publication pdf-reference-1.5" => "pdf-reference-1.5",
    "Adobe Publication pdf-reference-1.6" => "pdf-reference-1.6",
    "Adobe Publication pdf-reference-1.7" => "pdf-reference-1.7",
    "Adobe Publication postscript-language-reference-3.0" =>
      "postscript-language-reference-3.0",
    "Adobe Publication adobe-glyph-list" => "adobe-glyph-list",
    "Adobe Publication adobe-glyph-list-for-new-fonts" =>
      "adobe-glyph-list-for-new-fonts",
    "Adobe Publication pdf-signature-build-dictionary-1.4" =>
      "pdf-signature-build-dictionary-1.4",
    "Adobe Publication tiff-6.0" => "tiff-6.0",
    "Adobe Publication t1-spec" => "t1-spec",
    "Adobe Publication xfa-3.3" => "xfa-3.3",
    "Adobe Publication adobe-japan1-7" => "adobe-japan1-7",
    "Adobe Publication adobe-gb1-5" => "adobe-gb1-5"
  }.freeze

  # Cited, but relaton-data-adobe has no record yet: neither document has an
  # Adobe-hosted copy to crawl, so each needs a curated NormRefs entry. The
  # slugs are placeholders: when a record lands, move it to
  # cited_publications under its real slug (the pending example flips only
  # if the guess was right). A slug segment must not be all digits:
  # `adobe-supplement-iso-32000` parses as slug `adobe-supplement-iso`,
  # version `32000`.
  pending = {
    "Adobe Publication pdf-reference-1.1" =>
      "PDF 1.1 has no edition in adobe/dc-acrobat-sdk-docs pdfstandards/",
    "Adobe Publication adobe-supplement-iso32000" =>
      "the Adobe Supplement to the ISO 32000 has no Adobe-hosted copy " \
      "(the adobe.com URL redirects to the SDK docs landing page)"
  }.freeze

  # Cited by the PDF Association, but not Adobe records. PDF32000_2008.pdf
  # in adobe/dc-acrobat-sdk-docs is Adobe's courtesy copy of ISO 32000-1:2008,
  # an ISO document; relaton-data-adobe excludes it on purpose
  # (Sources::PdfStandards::EXCLUDED). A citing document cites the ISO id.
  cited_elsewhere = {
    "ISO 32000-1:2008" => :relaton_iso
  }.freeze

  # Read from a temporary copy: `Index::FileIO` writes a `.ms` sidecar next
  # to the file it reads, and it must not land in spec/adobe/fixtures/.
  def self.index_type
    @index_type ||= begin
      @tmpdir = Dir.mktmpdir("relaton-adobe-corpus")
      file = File.join(@tmpdir, "index-v2.yaml")
      FileUtils.cp File.expand_path("../../fixtures/index-v2.yaml", __dir__), file
      Relaton::Index::Type.new(:adobe_corpus, file: file,
                                              pubid_class: ::Pubid::Adobe::Identifier).tap(&:index)
    end
  end

  def self.cleanup
    FileUtils.rm_rf @tmpdir if @tmpdir
    @index_type = @tmpdir = nil
  end

  after(:all) { self.class.cleanup }

  let(:registry) { Relaton::Db::Registry.instance }
  let(:endpoint) { Relaton::Adobe::Bibliography::ENDPOINT }

  before do
    allow(Relaton::Adobe::Bibliography).to receive(:index).and_return(self.class.index_type)
    stub_request(:get, %r{\A#{Regexp.escape endpoint}data/}).to_return do |req|
      docid = req.uri.path[%r{data/(.+)\.yaml\z}, 1]
      { status: 200, body: { "id" => docid, "type" => "standard",
                             "docidentifier" => [{ "content" => docid, "type" => "ADOBE",
                                                   "primary" => true }] }.to_yaml }
    end
  end

  it "covers the whole published index except the uncited records" do
    cited = (cited_tech_notes.values + cited_publications.values).map { |f| "data/#{f}.yaml" }
    uncited = self.class.index_type.index.map { |r| r[:file] } - cited
    expect(cited.size).to eq 30
    expect(uncited.size).to eq 22
    expect(uncited).to all(match(%r{\Adata/(atn\d{4}|acrobat-dc-font-policies)\.yaml\z}))
  end

  cited_tech_notes.merge(cited_publications).each do |ref, file|
    it "resolves #{ref}" do
      expect(::Pubid::Adobe.parse(ref).to_s).to eq ref
      expect(registry.route(ref).first).to eq :relaton_adobe

      expect(Relaton::Adobe::Bibliography.get(ref)).to be_a Relaton::Adobe::ItemData
      expect(a_request(:get, "#{endpoint}data/#{file}.yaml")).to have_been_made.once
    end
  end

  cited_elsewhere.each do |ref, flavor|
    it "routes #{ref} to #{flavor}, not to the Adobe flavor" do
      expect(registry.route(ref).first).to eq flavor
    end
  end

  pending.each do |ref, reason|
    it "resolves #{ref}" do
      pending reason
      expect(Relaton::Adobe::Bibliography.get(ref)).not_to be_nil
    end
  end
end
