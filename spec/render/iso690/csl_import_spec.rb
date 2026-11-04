# frozen_string_literal: true

require_relative "../spec_helper"
require "relaton/bib"
require "json"
require "tmpdir"

# The CSL importer: a CSL style's common properties become a CitationStyle
# instance the engine executes (styles as data, the downgrade direction).
# CSL's element-list engine is strictly richer — everything the import
# drops is declared in the instance's `requires`.
RSpec.describe Relaton::Render::Iso690::CslImport do
  let(:csl_json) { File.read(File.expand_path("../fixtures/csl-author-date.json", __dir__)) }
  let(:style) { described_class.from_json(csl_json) }

  it "names the instance from the CSL info block" do
    expect(style.name).to eq "Imported Author-Date Sample (CSL import)"
  end

  it "declares the dropped CSL features in requires" do
    expect(style.requires.join(" ")).to include("macros")
    expect(style.requires.join(" ")).to include("bibliography section")
  end

  it "crosswalks the citation variable run to slots" do
    expect(style.templates.citation).to eq "{{creator}}, {{date}}, {{title}}"
  end

  it "crosswalks the bibliography run, deduplicated, over the vocabulary" do
    expect(style.templates.reference).to eq(
      "{{creator}}. {{title}}. {{production}}. {{date}}. {{identifier}}",
    )
  end

  it "maps the name-form scalars" do
    expect(style.scheme.name_form.initials).to be true
    expect(style.scheme.name_form.initials_separator).to eq ". "
    expect(style.scheme.name_form.initials_period).to be true
    expect(style.scheme.name_form.inverted_all).to be true
  end

  it "round-trips through the Style key-value load" do
    yaml = style.to_yaml
    loaded = Relaton::Render::Iso690::Style.from_yaml(yaml)
    expect(loaded.templates.citation).to eq style.templates.citation
    expect(loaded.scheme.name_form.initials_separator).to eq ". "
  end

  it "the imported style renders a document end-to-end" do
    model = Relaton::Bib::Item.from_xml(<<~XML)
      <bibitem type="standard" xmlns="http://riboseinc.com/isoxml">
        <title type="main">Sample Rendered Standard</title>
        <docidentifier type="ISO">ISO 12345:2020</docidentifier>
        <date type="published"><on>2020</on></date>
        <contributor><role type="publisher"/><organization><name>Sample Publisher</name></organization></contributor>
      </bibitem>
    XML
    # The renderer resolves a style by name or YAML path: the imported
    # instance goes through its serialized form.
    file = File.join(Dir.mktmpdir, "imported-author-date.yml")
    File.write(file, style.to_yaml)
    out = Relaton::Render::Iso690::Renderer.render(model, style: file)
    expect(out).to include "Sample Rendered Standard"
  end
end
