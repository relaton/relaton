# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Relaton::Render::Iso690::Template do
  subject(:output) { described_class.new(source).evaluate(fields) }

  let(:field_class) { Relaton::Render::Iso690::Template::Field }
  let(:present_date) { true }
  let(:fields) do
    {
      "creator" => field_class[true, "FARRAR, Frederic William"],
      "title" => field_class[true, "_Eric, or Little by Little_"],
      "date" => field_class[present_date, "1971"],
      "series" => field_class[false, ""],
    }
  end

  context "with all fields present" do
    let(:source) { "{{creator}}. {{title}}. {{date}}." }

    it "joins fields through the literals between them" do
      expect(output).to eq "FARRAR, Frederic William. " \
                           "_Eric, or Little by Little_. 1971."
    end
  end

  context "with a middle field absent" do
    let(:source) { "{{creator}}. {{series}}. {{title}}." }

    it "joins the surviving fields" do
      expect(output).to eq "FARRAR, Frederic William. " \
                           "_Eric, or Little by Little_."
    end
  end

  context "with the final field absent" do
    let(:source) { "{{creator}}. {{title}}. {{date}}." }
    let(:present_date) { false }

    it "still terminates the output" do
      expect(output).to eq "FARRAR, Frederic William. " \
                           "_Eric, or Little by Little_."
    end
  end

  context "with a trailing separator after the last rendered field" do
    let(:source) { "{{surname}}, {{givenNames}}" }
    let(:fields) do
      { "surname" => field_class[true, "HOMER"],
        "givennames" => field_class[false, ""] }
    end

    it "gives up the separator" do
      expect(output).to eq "HOMER"
    end
  end

  context "with output already ending in the terminator" do
    let(:source) { "{{title}}." }

    it "does not double the terminator" do
      expect(output).to eq "_Eric, or Little by Little_."
    end
  end

  context "with a prefix literal" do
    let(:source) { "In: {{title}}." }

    it "attaches it to the field it prefixes" do
      expect(output).to eq "In: _Eric, or Little by Little_."
    end
  end

  context "with no field present" do
    let(:source) { "{{creator}}. {{date}}." }
    let(:fields) do
      { "creator" => field_class[false, ""],
        "date" => field_class[false, ""] }
    end

    it { is_expected.to be_empty }
  end

  context "with a sentence period colliding with a comma or period" do
    let(:fields) do
      { "title" => field_class[true, "_Cereals_"],
        "serialdate" => field_class[true, ", 2013–2014"],
        "identifier" => field_class[true, "ISO 20483"] }
    end
    let(:source) { "{{title}}. {{serialdate}}. {{identifier}}." }

    it "collapses the periods into the comma (the serial date owns the
        separator)" do
      expect(output).to eq "_Cereals_, 2013–2014. ISO 20483."
    end
  end

  context "with a fallback ending in its own period" do
    let(:fields) do
      { "title" => field_class[true, "_A journal_"],
        "date" => field_class[true, "n.d."],
        "identifier" => field_class[true, "ISSN: ISSN"] }
    end
    let(:source) { "{{title}}. {{date}}. {{identifier}}." }

    it "does not double the period" do
      expect(output).to eq "_A journal_. n.d. ISSN: ISSN."
    end
  end

  context "with absent elements between present ones (1.x segment join)" do
    let(:fields) do
      { "title" => field_class[true, "_A book_"],
        "medium" => field_class[false, ""],
        "edition" => field_class[false, ""],
        "production" => field_class[true, "London: Hamilton"],
        "date" => field_class[true, "1971"] }
    end
    let(:source) do
      "{{title}}. {{medium}}. {{edition}}. {{production}}. {{date}}."
    end

    it "joins the present elements with one separator" do
      expect(output).to eq "_A book_. London: Hamilton. 1971."
    end
  end

  context "with a paired literal around a trailing present element" do
    let(:fields) do
      { "title" => field_class[true, "_A book_"],
        "production" => field_class[true, "London: Hamilton"],
        "series" => field_class[false, ""] }
    end
    let(:source) { "{{title}}. ({{production}}) {{series}}." }

    it "closes the pair when nothing follows it (the enclosing pass
        tidies the spacing before the terminator)" do
      expect(output).to eq "_A book_. (London: Hamilton) ."
    end
  end

  context "with markup closing an absent element's group" do
    let(:fields) do
      { "seriestitle" => field_class[true, "Metrologia"],
        "seriesrun" => field_class[false, ""] }
    end
    let(:source) { "{{seriesTitle}} ({{seriesRun}})" }

    it "keeps the structural close for the enclosing template" do
      expect(output.rstrip).to eq "Metrologia"
    end
  end

  context "with slot names differing in case or underscores" do
    let(:fields) do
      { "componentpart" => field_class[true, "In: _A host_"],
        "date" => field_class[true, "1971"] }
    end
    let(:source) { "{{Component_Part}} {{date}}." }

    it "resolves them identically" do
      expect(output).to eq "In: _A host_ 1971."
    end
  end
end
