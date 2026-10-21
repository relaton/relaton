require "spec_helper"
require "relaton/iec"

describe Relaton::Iec::ProjectParser do
  # Shape follows the IEC/ISO Harmonized APIs technical documentation
  # ("HAPI - Projects"): stage lifecycle inline, projectRelations by URN,
  # publications links added once the project reaches PPUB (60.60).
  subject(:bib) { described_class.new(project).parse }

  let(:project) do
    {
      "urn" => "iec:proj:1000006047",
      "reference" => "IEC 60034-4:2008 ED3",
      "sortKey" => "A006003400041000 97.0000000000",
      "stdType" => "IS",
      "edition" => "3",
      "title" => [
        { "lang" => "en",
          "value" => "Rotating electrical machines - Part 4: Methods for determining "                      "synchronous machine quantities from tests" },
        { "lang" => "fr", "value" => "Machines électriques tournantes - Partie 4" },
      ],
      "abstract" => [{ "lang" => "en", "content" => "Applies to three-phase synchronous machines." }],
      "classifications" => [{ "type" => "ICS", "value" => "29.160.10" }],
      "languageSettings" => [{ "multilingual" => true, "language" => %w[en fr] }],
      "owner" => { "urn" => "iec:org:1221", "targetType" => "COMMITTEE", "displayName" => "TC 2" },
      "editionDate" => "2008-05-13",
      "initialProjectDate" => "2004-01-30",
      "forecastPublicationDate" => "2026-12-01",
      "stages" => [
        { "stageCode" => "RFDIS", "harmonizedStageCode" => "50.00", "iteration" => 1,
          "status" => "CLOSED", "effectiveDate" => "2020-06-25" },
        { "stageCode" => "CFDIS", "harmonizedStageCode" => "50.20", "iteration" => 1,
          "status" => "CURRENT", "effectiveDate" => "2020-09-11", "nextStageDate" => "2020-10-23" },
        { "stageCode" => "PRVD", "harmonizedStageCode" => "50.60", "iteration" => 1,
          "status" => "PLANNED" },
      ],
      "projectRelations" => [
        { "type" => "REPLACED_BY", "urn" => "iec:proj:22980" },
        { "type" => "AMENDS", "urn" => "iec:proj:335" },
        { "type" => "FRANKFURT_AGREEMENT",
          "externalProject" => { "displayName" => "EN 61000-3-12:2011/prA1:2019", "projectId" => 684_76 } },
      ],
      "publications" => [{ "urn" => "iec:pub:138", "urnAlt" => "iec:std:iec:60034-4:2008-05::" }],
      "lastChangeTimestamp" => "2026-10-21T02:37:15Z",
    }
  end

  it "builds the IEC primary docidentifier and the raw project URN" do
    ids = bib.docidentifier.map { |d| [d.type, d.content.to_s] }
    expect(ids).to include(["IEC", "IEC 60034-4:2008 ED3"])
    expect(ids).to include(["URN", "iec:proj:1000006047"])
    expect(bib.docidentifier.detect(&:primary).type).to eq("IEC")
  end

  it "carries the CURRENT stage as status" do
    expect(bib.status.stage.abbreviation).to eq("CFDIS")
    expect(bib.status.stage.content).to eq("50.20")
    expect(bib.status.iteration).to eq("1")
  end

  it "falls back to the last stage when none is CURRENT" do
    project["stages"] = [{ "stageCode" => "WPUB", "harmonizedStageCode" => "60.00",
                           "iteration" => 1, "status" => "CLOSED" }]
    expect(bib.status.stage.abbreviation).to eq("WPUB")
  end

  it "maps projectRelations onto the bibdata vocabulary" do
    types = bib.relation.map { |r| [r.type, r.bibitem.docidentifier.first.content] }
    expect(types).to include(["obsoletedBy", "iec:proj:22980"])
    expect(types).to include(["updates", "iec:proj:335"])
  end

  it "skips relations that carry no URN (external agreements)" do
    targets = bib.relation.map { |r| r.bibitem.docidentifier.first.content }
    expect(targets).not_to include(a_string_matching(/EN 61000/))
  end

  it "links the realized publications as successors" do
    succ = bib.relation.find { |r| r.type == "hasSuccessor" }
    expect(succ.bibitem.docidentifier.first.content).to eq("iec:pub:138")
  end

  it "parses titles, dates and the owner committee" do
    expect(bib.title.map { |t| t.content.to_s }.first).to include("Rotating electrical machines")
    types = bib.date.map { |d| [d.type, d.at.to_s] }
    expect(types).to include(["published", "2008-05-13"])
    expect(types).to include(["created", "2004-01-30"])
    expect(types).to include(["forecast", "2026-12-01"])
    tc = bib.contributor.flat_map { |c| c.organization.subdivision }.find { |s| s.type == "technical-committee" }
    expect(tc.name.first.content).to eq("TC 2")
  end

  it "round-trips through YAML" do
    yaml = bib.to_yaml
    round = Relaton::Iec::Item.from_yaml(yaml)
    expect(round.docidentifier.detect(&:primary).content.to_s).to eq("IEC 60034-4:2008 ED3")
    expect(round.status.stage.abbreviation).to eq("CFDIS")
  end
end
