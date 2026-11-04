# frozen_string_literal: true

require_relative "../spec_helper"
require "relaton/bib"
require "tmpdir"

RSpec.describe "renderer element maps" do
  def bib(xml)
    Relaton::Bib::Bibitem.from_xml(xml)
  end

  let(:no_author) do
    bib(<<~X)
      <bibitem type="standard">
        <title>Cereals and cereal products</title>
        <docidentifier type="ISO">ISO 712</docidentifier>
        <contributor><role type="publisher"/>
          <organization><name>International Organization</name></organization>
        </contributor>
      </bibitem>
    X
  end

  let(:flavor_style) do
    path = File.join(Dir.mktmpdir, "flavor.yml")
    File.write(path, <<~Y)
      name: flavor slot style
      scheme:
        system: name-date
      templates:
        titleOpen: "_"
        titleClose: "_"
        reference: "{{creator}}. {{title}}{{flavourmark}}. {{identifier}}."
    Y
    path
  end

  it "resolves a flavor slot and a built-in override through the
      elements option alone" do
    marker = Class.new(Relaton::Render::Iso690::Element) do
      def present?
        true
      end

      def render
        " (flavor)"
      end
    end
    creator = Class.new(Relaton::Render::Iso690::Elements::Creator) do
      def present?
        true
      end

      def render
        "Flavor Creator"
      end

      def in_text
        "Flavor"
      end

      def principal_given
        ""
      end
    end
    out = Relaton::Render::Iso690::Renderer.new(
      style: flavor_style,
      elements: { flavourmark: marker, creator: creator },
    ).render(no_author)
    expect(out).to eq "Flavor Creator. _Cereals and cereal products_" \
                      " (flavor). ISO 712."
  end

  it "leaves other renderers of the same process untouched" do
    marker = Class.new(Relaton::Render::Iso690::Element) do
      def present?
        true
      end

      def render
        " (flavor)"
      end
    end
    flavored = Relaton::Render::Iso690::Renderer.new(
      style: flavor_style, elements: { flavourmark: marker },
    )
    plain = Relaton::Render::Iso690::Renderer.new(style: flavor_style)
    expect(flavored.render(no_author)).to include("(flavor)")
    expect(plain.render(no_author)).not_to include("(flavor)")
  end

  it "renders the publisher's name as the creator fallback when a
      style declares it" do
    style = File.join(Dir.mktmpdir, "publisher-name.yml")
    File.write(style, <<~Y)
      name: publisher-name creator fallback
      scheme:
        system: name-date
        nameForm:
          creatorFallback: publisher_name
      templates:
        titleOpen: "_"
        titleClose: "_"
        reference: "{{creator}}. {{title}}. {{identifier}}."
    Y
    out = Relaton::Render::Iso690::Renderer.new(style: style)
      .render(no_author)
    expect(out)
      .to eq "International Organization. " \
             "_Cereals and cereal products_. ISO 712."
  end

  it "renders an identifier kind through an Identifier subclass,
      not a process-wide registry" do
    identifier = Class.new(Relaton::Render::Iso690::Elements::Identifier) do
      def render_id(docidentifier)
        return "#{docidentifier.type}: #{docidentifier.content}" if
          docidentifier.type == "ISO"

        super
      end
    end
    out = Relaton::Render::Iso690::Renderer.new(
      style: "author-date", elements: { identifier: identifier },
    ).render(no_author)
    expect(out).to include("ISO: ISO 712")
  end
end

RSpec.describe Relaton::Render::Iso690::Elements::Authorizer do
  it "cites the authorizing body" do
    xml = <<~X
      <bibitem type="standard">
        <title>T</title>
        <contributor><role type="authorizer"/>
          <organization><name>RFC Series</name></organization>
        </contributor>
      </bibitem>
    X
    model = Relaton::Bib::Bibitem.from_xml(xml)
    style = Relaton::Render::Iso690::Style.load("author-date")
    i18n = Relaton::Render::Iso690::I18n.load("en")
    element = described_class.new(model, style: style, i18n: i18n)
    expect(element.render).to eq "RFC Series"
  end
end

RSpec.describe "batch disambiguation and name-form knobs" do
  def bib(xml)
    Relaton::Bib::Bibitem.from_xml(xml)
  end

  def two_books(suffix)
    <<~X
      <bibitem type="book" id="a1">
        <title>First book on #{suffix}</title>
        <docidentifier type="ISBN">ISBN 1</docidentifier>
        <date type="published"><on>2022</on></date>
        <contributor><role type="author"/>
          <person><name><surname>Aluffi</surname><forename>Paolo</forename></name></person>
        </contributor>
        <contributor><role type="author"/>
          <person><name><surname>Payne</surname><forename>Sam</forename></name></person>
        </contributor>
      </bibitem>
      <bibitem type="book" id="a2">
        <title>Second book on #{suffix}</title>
        <docidentifier type="ISBN">ISBN 2</docidentifier>
        <date type="published"><on>2022</on></date>
        <contributor><role type="author"/>
          <person><name><surname>Aluffi</surname><forename>Paolo</forename></name></person>
        </contributor>
        <contributor><role type="author"/>
          <person><name><surname>Payne</surname><forename>Sam</forename></name></person>
        </contributor>
      </bibitem>
    X
  end

  it "suffixes colliding creator-date pairs in render_all" do
    style = File.join(Dir.mktmpdir, "disambig.yml")
    File.write(style, <<~Y)
      name: disambiguated-date style
      scheme:
        system: name-date
      templates:
        titleOpen: "_"
        titleClose: "_"
        reference: "{{creator}}. {{title}}. {{disambiguateddate}}."
    Y
    refs = Relaton::Render::General.new(style: style).render_all(
      "<references>#{two_books('one')}</references>",
    )
    expect(refs["a1"][:formattedref]).to include("2022a")
    expect(refs["a2"][:formattedref]).to include("2022b")
  end

  it "truncates the in-text cite at the et-al threshold" do
    style = File.join(Dir.mktmpdir, "etal.yml")
    File.write(style, <<~Y)
      name: et-al style
      scheme:
        system: name-date
        nameForm:
          etalCount: 3
      templates:
        titleOpen: "_"
        titleClose: "_"
        citation: "{{surname}}, {{date}}"
        reference: "{{creator}}. {{title}}. {{date}}."
    Y
    model = bib(<<~X)
      <bibitem type="book">
        <title>T</title>
        <date type="published"><on>2020</on></date>
        <contributor><role type="author"/><person><name><surname>A</surname><forename>X</forename></name></person></contributor>
        <contributor><role type="author"/><person><name><surname>B</surname><forename>Y</forename></name></person></contributor>
        <contributor><role type="author"/><person><name><surname>C</surname><forename>Z</forename></name></person></contributor>
      </bibitem>
    X
    out = Relaton::Render::Iso690::Renderer.new(style: style).citation(model)
    # The et-al suffix renders the locale's `others` label, roman by
      # default — a style wanting emphasis sets `others:` with markup
      expect(out).to eq "A et al., 2020"
  end

  it "truncates the in-text cite at its own et-al threshold" do
    style = File.join(Dir.mktmpdir, "intext-etal.yml")
    File.write(style, <<~Y)
      name: in-text et-al style
      scheme:
        system: name-date
        nameForm:
          etalCount: 6
          inTextEtalCount: 3
          inTextEtalDisplay: 1
      templates:
        titleOpen: "_"
        titleClose: "_"
        reference: "{{creator}}. {{title}}. {{date}}."
    Y
    model = bib(<<~X)
      <bibitem type="book">
        <title>T</title>
        <contributor><role type="author"/><person><name><surname>A</surname><forename>X</forename></name></person></contributor>
        <contributor><role type="author"/><person><name><surname>B</surname><forename>Y</forename></name></person></contributor>
        <contributor><role type="author"/><person><name><surname>C</surname><forename>Z</forename></name></person></contributor>
      </bibitem>
    X
    renderer = Relaton::Render::Iso690::Renderer.new(style: style)
    expect(renderer.in_text_author(model)).to eq "A et al."
  end

  it "composes the author-date capsule with its disambiguator" do
    style = File.join(Dir.mktmpdir, "capsule.yml")
    File.write(style, <<~Y)
      name: capsule style
      scheme:
        system: name-date
      templates:
        titleOpen: "_"
        titleClose: "_"
        reference: "{{creator}}. {{title}}. {{date}}."
    Y
    model = bib(<<~X)
      <bibitem type="book">
        <title>T</title>
        <date type="published"><on>2020</on></date>
        <contributor><role type="author"/><person><name><surname>A</surname><forename>X</forename></name></person></contributor>
      </bibitem>
    X
    out = Relaton::Render::Iso690::Renderer.new(style: style)
      .author_date_citation(model, disambiguator: "a")
    expect(out).to eq "A 2020a"
  end

  it "exposes the 1.x renderings keys to isodoc" do
    style = File.join(Dir.mktmpdir, "renderings.yml")
    File.write(style, <<~Y)
      name: renderings style
      scheme:
        system: name-date
      templates:
        titleOpen: "_"
        titleClose: "_"
        reference: "{{creator}}. {{title}}. {{date}}."
    Y
    refs = Relaton::Render::General.new(style: style).render_all(
      "<references>#{two_books('one')}</references>",
    )
    expect(refs["a1"][:author]).to eq "ALUFFI"
    expect(refs["a1"][:citation][:author_date]).to eq "ALUFFI, 2022"
    expect(refs["a1"][:citation][:default]).to eq "ISBN 1"
    expect(refs["a1"][:citation][:author]).to eq "ALUFFI"
    expect(refs["a1"][:citation][:title]).to eq "First book on one"
    expect(refs["a1"][:citation][:author_date_br]).to eq "ALUFFI (2022)"
    expect(refs["a1"][:citation][:date]).to eq "2022"
    expect(refs["a1"][:citation][:reference_tag]).to be_nil
    expect(refs["a1"][:citation][:title_reference_tag])
      .to eq "First book on one"
  end

  it "keeps subsequent surnames mixed-case when the style declares it" do
    style = File.join(Dir.mktmpdir, "mixed.yml")
    File.write(style, <<~Y)
      name: mixed subsequent style
      scheme:
        system: name-date
        nameForm:
          initials: true
          surnameUpcase: false
          subsequentSurnameUpcase: false
      templates:
        titleOpen: "_"
        titleClose: "_"
        reference: "{{creator}}. {{title}}. {{date}}."
        name: "{{surname}}, {{givenNames}}"
    Y
    model = bib(<<~X)
      <bibitem type="book">
        <title>T</title>
        <date type="published"><on>2020</on></date>
        <contributor><role type="author"/><person><name><surname>Aluffi</surname><forename>Paolo</forename></name></person></contributor>
        <contributor><role type="author"/><person><name><surname>Payne</surname><forename>Sam</forename></name></person></contributor>
      </bibitem>
    X
    out = Relaton::Render::Iso690::Renderer.new(style: style).render(model)
    expect(out).to eq "Aluffi, P. and S. Payne. _T_. 2020."
  end
end

RSpec.describe "creator-list et-al truncation" do
  it "truncates the creator list at the style's thresholds" do
    style = File.join(Dir.mktmpdir, "etal-list.yml")
    File.write(style, <<~Y)
      name: et-al list style
      scheme:
        system: name-date
        nameForm:
          etalCount: 6
          etalDisplay: 3
      templates:
        titleOpen: "_"
        titleClose: "_"
        reference: "{{creator}}. {{title}}. {{date}}."
        name: "{{surname}}, {{givenNames}}"
    Y
    people = (1..7).map do |i|
      "<contributor><role type=\"author\"/><person><name>" \
        "<surname>S#{i}</surname><forename>F#{i}</forename></name>" \
        "</person></contributor>"
    end.join
    require "nokogiri"
    model = Relaton::Bib::Bibitem.from_xml(<<~X)
      <bibitem type="book">
        <title>T</title>
        <date type="published"><on>2020</on></date>
        #{people}
      </bibitem>
    X
    out = Relaton::Render::Iso690::Renderer.new(style: style).render(model)
    expect(out)
      .to eq "S1, F1, F2 S2, F3 S3 et al. _T_. 2020."
  end
end

RSpec.describe "subsequent initials name form" do
  it "cites the first forename in full, the rest as initials" do
    style = File.join(Dir.mktmpdir, "history-names.yml")
    File.write(style, <<~Y)
      name: history-names style
      scheme:
        system: name-date
        nameForm:
          initials: true
          subsequentInitials: true
          initialsPeriod: true
      templates:
        titleOpen: "_"
        titleClose: "_"
        name: "{{surname}}, {{givenNames}}"
        reference: "{{creator}}. {{title}}. {{date}}."
    Y
    model = Relaton::Bib::Bibitem.from_xml(<<~X)
      <bibitem type="book">
        <title>T</title>
        <contributor><role type="author"/>
          <person><name><surname>Hering</surname><forename>Milena</forename><forename>Sofia</forename></name></person>
        </contributor>
      </bibitem>
    X
    out = Relaton::Render::Iso690::Renderer.new(style: style)
      .render_creators(model)
    expect(out).to eq "HERING, Milena S."
  end
end
