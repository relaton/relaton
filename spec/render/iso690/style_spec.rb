# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Relaton::Render::Iso690::Style do
  describe ".load" do
    it "loads a named instance from the styles directory" do
      expect(described_class.load("author-date").name)
        .to eq "ISO 690 (name and date)"
    end

    it "loads an instance by path" do
      path = File.join(__dir__, "../fixtures/style-variant.yml")
      expect(described_class.load(path).name).to eq "variant"
    end

    it "raises for an unknown style" do
      expect { described_class.load("turbabian") }
        .to raise_error ArgumentError, /unknown style turbabian/
    end
  end

  describe "#template_for" do
    subject(:style) { described_class.load("author-date") }

    it "selects the per-type template by clause 8 kind lookup" do
      expect(style.template_for("continuing")).to include "{{componentPart}}"
    end

    it "falls back to the general reference template" do
      expect(style.template_for("moving-image"))
        .to eq style.templates.reference
    end
  end

  describe "#render_name" do
    subject(:style) { described_class.load("author-date") }

    it "upcases the surname through the name template" do
      expect(style.render_name(surname: "Farrar", given: "Frederic William"))
        .to eq "FARRAR, Frederic William"
    end

    it "drops the separator with an absent given name" do
      expect(style.render_name(surname: "Homer", given: "")).to eq "HOMER"
    end
  end

  describe "scheme locale" do
    it "overlays the language pack" do
      style = described_class.load(
        File.join(__dir__, "../fixtures/style-variant.yml"),
      )
      i18n = Relaton::Render::Iso690::I18n.load("fr").overlay!(
        style.scheme.locale,
      )
      expect(i18n.label("and")).to eq "ainsi que"
    end
  end
end

RSpec.describe Relaton::Render::Iso690::Style do
  context "canonical jis packs" do
    it "loads by registry name and carries the jis scheme" do
      style = described_class.load("jis-en")
      expect(style.family).to eq "iso690"
      expect(style.scheme.short_from_reference).to be(true)
      expect(style.per_type.map(&:type)).to include("report", "monograph")
    end
  end

  context "delta packs" do
    def write_pack(name, yaml)
      path = File.join(Dir.mktmpdir, "#{name}.yml")
      File.write(path, yaml)
      path
    end

    it "merges perType per type key, keeps the base's other patterns" do
      base = write_pack("delta-base", <<~YML)
        name: delta base
        perType:
          - type: monograph
            template: "BASE {{title}}"
          - type: article
            template: "BASE-A {{title}}"
      YML
      delta = write_pack("delta-pack", <<~YML)
        name: delta pack
        extends: #{base}
        perType:
          - type: article
            template: "DELTA-A {{title}}"
      YML
      style = described_class.load(delta)
      expect(style.template_for("article")).to eq "DELTA-A {{title}}"
      expect(style.template_for("monograph")).to eq "BASE {{title}}"
    end

    it "merges labels per key and name-form knobs only when undeclared" do
      base = write_pack("label-base", <<~YML)
        name: label base
        scheme:
          nameForm:
            invertedAll: true
            initials: true
          locale:
            labels:
              "and": "&"
      YML
      delta = write_pack("label-pack", <<~YML)
        name: label pack
        extends: #{base}
        scheme:
          nameForm:
            surnameUpcase: false
          locale:
            labels:
              series_no: ""
      YML
      style = described_class.load(delta)
      # a knob at the model default counts as unset: it inherits
      expect(style.scheme.name_form.surname_upcase).to be(false) # declared wins
      expect(style.scheme.name_form.initials).to be(true) # inherited
      expect(style.scheme.name_form.inverted_all).to be(true) # inherited
      expect(style.scheme.locale.label_map["and"]).to eq "&" # inherited
      expect(style.scheme.locale.label_map["series_no"]).to eq "" # declared
    end

    it "lets a delta label win per key and a named attribute assert over the base's labels" do
      base = write_pack("label-base2", <<~YML)
        name: label base 2
        scheme:
          locale:
            availableAt: "Available at:"
            labels:
              "and": "&"
      YML
      delta = write_pack("label-delta2", <<~YML)
        name: label delta 2
        extends: #{base}
        scheme:
          locale:
            availableAt: "\u5165\u624B\u5148\uFF1A"
            labels:
              "and": ""
      YML
      style = described_class.load(delta)
      expect(style.scheme.locale.label_map["and"]).to eq "" # declared wins
      expect(style.scheme.locale.label_map["available_from"])
        .to eq "\u5165\u624B\u5148\uFF1A" # named attribute asserts
    end

    it "unions requires and resolves the pack taxonomy before Kinds" do
      base = write_pack("req-base", <<~YML)
        name: req base
        requires: [production_order]
      YML
      delta = write_pack("req-pack", <<~YML)
        name: req pack
        extends: #{base}
        requires: [extent_units]
        types:
          article-journal: continuing
          dataset: webdoc
      YML
      style = described_class.load(delta)
      expect(style.requires.sort).to eq %w[extent_units production_order]
      expect(style.kind_for("article-journal")).to eq "continuing"
      expect(style.kind_for("dataset")).to eq "webdoc"
      expect(style.kind_for("book")).to eq "monograph" # Kinds fallthrough
    end
  end
end
