# frozen_string_literal: true

require_relative "spec_helper"
require "relaton/bib"

# relaton-render#90: isodoc main's render-isodoc subclasses
# Relaton::Render::General (`class General < ::Relaton::Render::General`)
# and constructs it with the v1 option set (language:, script:, i18nhash:,
# config:). The constant must exist and boot; rendering delegates to the
# v2 engine; the retired liquid config warns once.
RSpec.describe Relaton::Render::General do
  let(:item) do
    Relaton::Bib::Bibitem.from_xml(<<~X)
      <bibitem type="book">
        <title>Eric, or Little by Little</title>
        <date type="published"><on>1971</on></date>
        <contributor><role type="author"/>
          <person><name><surname>Farrar</surname><forename>Frederic</forename></name></person>
        </contributor>
      </bibitem>
    X
  end

  it "accepts the v1 option set and renders through the v2 engine" do
    renderer = described_class.new(
      language: "en", script: "Latn", i18nhash: {}, config: nil,
    )
    # bare with embedded:, formattedref-wrapped by default (the 1.x
    # render contract the flavors and isodoc consume)
    expect(renderer.render(item, embedded: true))
      .to eq "FARRAR, Frederic. _Eric, or Little by Little_. 1971."
    expect(renderer.render(item))
      .to eq "<formattedref>FARRAR, Frederic. " \
             "_Eric, or Little by Little_. 1971.</formattedref>"
    expect(renderer.citation(item)).to eq "FARRAR, 1971"
  end

  it "applies a runtime i18n hash to the language pack" do
    renderer = described_class.new(
      language: "en", script: "Latn",
      i18nhash: { "and" => "und", "edition" => "Aufl." },
    )
    two_authors = Relaton::Bib::Bibitem.from_xml(<<~X)
      <bibitem type="book">
        <title>Two authors</title>
        <date type="published"><on>2000</on></date>
        <contributor><role type="author"/>
          <person><name><surname>One</surname></name></person>
        </contributor>
        <contributor><role type="author"/>
          <person><name><surname>Two</surname></name></person>
        </contributor>
      </bibitem>
    X
    expect(renderer.render(two_authors)).to include "ONE und TWO"
  end

  it "warns exactly once that the liquid config is retired" do
    expect do
      described_class.new(language: "en", config: { "template" => {} })
      described_class.new(language: "en", config: { "template" => {} })
    end.to output(/compatibility facade.*retired and ignored/m).to_stderr
  end

  describe "#render_all — isodoc's references rendering entry" do
    it "keys renderings by bibitem id with formattedref and citations" do
      renderer = described_class.new(language: "en", script: "Latn")
      renderings = renderer.render_all(<<~X)
        <references>
          <bibitem id="f1" type="book">
            <title>Eric, or Little by Little</title>
            <date type="published"><on>1971</on></date>
            <contributor><role type="author"/>
              <person><name><surname>Farrar</surname><forename>Frederic</forename></name></person>
            </contributor>
          </bibitem>
        </references>
      X
      expect(renderings["f1"][:formattedref])
        .to eq "FARRAR, Frederic. _Eric, or Little by Little_. 1971."
      expect(renderings["f1"][:citation][:short]).to eq "FARRAR, 1971"
    end

    it "returns nil for input without bibitems, as 1.x did" do
      expect(described_class.new(language: "en").render_all("<other/>")).to be_nil
    end

    it "skips bibitems whose template resolves to nothing" do
      renderings = described_class.new(language: "en").render_all(<<~X)
        <references>
          <bibitem id="f1" type="book">
            <title>Eric, or Little by Little</title>
            <date type="published"><on>1971</on></date>
            <contributor><role type="author"/>
              <person><name><surname>Farrar</surname><forename>Frederic</forename></name></person>
            </contributor>
          </bibitem>
          <bibitem id="empty"/>
        </references>
      X
      expect(renderings.keys).to eq ["f1"]
    end
  end

  describe "#parse — isodoc's pref_ref_code entry" do
    it "extracts the authoritative identifiers from a bibitem node" do
      renderer = described_class.new(language: "en")
      doc = Moxml.parse(<<~X).root
        <bibitem id="x" type="standard">
          <docidentifier type="ISO" primary="true">ISO 19115-1:2014</docidentifier>
          <docidentifier type="urn">urn:iso:std:iso:19115:-1:ed-1:en</docidentifier>
        </bibitem>
      X
      data, = renderer.parse(doc)
      expect(data[:authoritative_identifier]).to eq ["<esc>ISO 19115-1:2014</esc>"]
    end

    it "finds docidentifiers on a node that still carries the document " \
       "namespace (isodoc passes the live bibitem element)" do
      renderer = described_class.new(language: "en")
      doc = Moxml.parse(<<~X).root
        <bibitem id="ISO712" type="standard" xmlns="http://riboseinc.com/isoxml">
          <docidentifier type="ISO">ISO 712</docidentifier>
        </bibitem>
      X
      data, = renderer.parse(doc)
      expect(data[:authoritative_identifier]).to eq ["<esc>ISO 712</esc>"]
    end

    it "keeps only the primary identifiers when a cascade tier matches, " \
       "excludes DOI/ISBN/ISSN types, and drops scoped duplicates" do
      renderer = described_class.new(language: "en")
      doc = Moxml.parse(<<~X).root
        <bibitem id="x" type="standard">
          <docidentifier type="IETF">RFC 2119</docidentifier>
          <docidentifier type="DOI">10.17487/RFC2119</docidentifier>
          <docidentifier type="ISSN">1234-5678</docidentifier>
          <docidentifier scope="biblio-tag">RFC 2119</docidentifier>
        </bibitem>
      X
      data, = renderer.parse(doc)
      expect(data[:authoritative_identifier]).to eq ["<esc>RFC 2119</esc>"]
    end

    it "falls through the cascade to all identifiers when none is primary" do
      renderer = described_class.new(language: "en")
      doc = Moxml.parse(<<~X).root
        <bibitem id="x" type="standard">
          <docidentifier type="ISO">ISO 712</docidentifier>
          <docidentifier type="IEC">IEC 61082</docidentifier>
        </bibitem>
      X
      data, = renderer.parse(doc)
      expect(data[:authoritative_identifier]).to eq ["<esc>ISO 712</esc>", "<esc>IEC 61082</esc>"]
    end
  end

  describe "#citetemplate — standoc's eref style vocabulary" do
    it "exposes the 1.x style names as template_raw keys" do
      keys = described_class.new(language: "en").citetemplate.template_raw.keys
      expect(keys).to include(:author_date, :author, :short, :reference_tag)
    end
  end
end

RSpec.describe "Relaton::Render::General option keys" do
  it "accepts the string-keyed options isodoc's bibrenderer passes" do
    r = Relaton::Render::General.new("language" => "en", "script" => "Latn")
    expect(r.instance_variable_get(:@lang)).to eq "en"
    expect(r.instance_variable_get(:@renderer)
      .instance_variable_get(:@script)).to eq "Latn"
  end
end

RSpec.describe "Relaton::Render::General style option" do
  it "loads a flavor's CitationStyle by path" do
    r = Relaton::Render::General.new(language: "en", style: File.join(__dir__, "fixtures/probe-style.yml"))
    model = Relaton::Bib::Bibitem.from_xml(
      "<bibitem type='standard'><title language='en'>T</title>" \
      "<docidentifier type='ISO'>ISO 1</docidentifier>" \
      "<contributor><role type='author'/><person><name>" \
      "<surname>Doe</surname></name></person></contributor>" \
      "<date type='published'><on>2020</on></date></bibitem>")
    expect(r.render(model)).to include "DOE"
  end
end

RSpec.describe "Relaton::Render::General XML-string input" do
  it "renders a bibitem XML string like the 1.x engine did" do
    r = Relaton::Render::General.new(language: "en")
    out = r.render("<bibitem type='standard'><title language='en'>T</title>" \
      "<contributor><role type='author'/><person><name><surname>Doe</surname>" \
      "</name></person></contributor></bibitem>")
    expect(out).to include "DOE"
  end
end
