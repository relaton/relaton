# frozen_string_literal: true

# Edge round-trip laws (TODO.sota stream 4): a relation type and its target
# document survive both serialization forms unchanged, for every relation type
# the model declares.
describe Relaton::Bib::Relation do
  # Kept in step with the `values:` list on Relation#type. A type added there
  # without a line here is still constrained by the model, but its round-trip
  # is not exercised; add it with the model change.
  RELATION_TYPES = %w[
    includes includedIn hasPart partOf merges mergedInto splits splitInto
    instanceOf hasInstance exemplarOf hasExemplar manifestationOf
    hasManifestation reproductionOf hasReproduction reprintOf hasReprint
    expressionOf hasExpression translatedFrom hasTranslation arrangementOf
    hasArrangement abridgementOf hasAbridgement annotationOf hasAnnotation
    draftOf hasDraft predecessorDraftOf hasPredecessorDraft successorDraftOf
    hasSuccessorDraft editionOf hasEdition updates updatedBy derivedFrom
    derives describes describedBy catalogues cataloguedBy hasSuccessor
    successorOf adaptedFrom hasAdaptation adoptedFrom adoptedAs reviewOf
    hasReview commentaryOf hasCommentary related hasComplement complementOf
    obsoletes obsoletedBy cites isCitedIn
  ].freeze

  let(:target) do
    Relaton::Bib::ItemData.new(
      title: [Relaton::Bib::Title.new(type: "main", content: "Target document",
                                      language: "en", script: "Latn")],
      docidentifier: [Relaton::Bib::Docidentifier.new(content: "ISO 1", type: "ISO")],
    )
  end

  it "preserves every relation type and its target through YAML" do
    RELATION_TYPES.each do |type|
      relation = described_class.new(type: type, bibitem: target)
      round = described_class.from_yaml(relation.to_yaml)

      expect(round.type).to eq(type), "YAML lost relation type #{type}"
      expect(round.bibitem.title.first.content).to eq("Target document")
      expect(round.bibitem.docidentifier.first.content).to eq("ISO 1")
    end
  end

  it "preserves every relation type and its target through XML" do
    RELATION_TYPES.each do |type|
      relation = described_class.new(type: type, bibitem: target)
      round = described_class.from_xml(relation.to_xml)

      expect(round.type).to eq(type), "XML lost relation type #{type}"
      expect(round.bibitem.title.first.content).to eq("Target document")
      expect(round.bibitem.docidentifier.first.content).to eq("ISO 1")
    end
  end

  it "keeps a bidirectional pair's edges through serialization" do
    # Published data stores each direction in its own record, with the target
    # as a shallow snapshot: the pair is reconstructed by fetching both, not by
    # one record holding a cycle.
    a_ref = Relaton::Bib::ItemData.new(
      title: [Relaton::Bib::Title.new(type: "main", content: "A", language: "en")],
      docidentifier: [Relaton::Bib::Docidentifier.new(content: "ISO 1", type: "ISO")],
    )
    b_ref = Relaton::Bib::ItemData.new(
      title: [Relaton::Bib::Title.new(type: "main", content: "B", language: "en")],
      docidentifier: [Relaton::Bib::Docidentifier.new(content: "ISO 2", type: "ISO")],
    )
    a = Relaton::Bib::ItemData.new(
      title: a_ref.title,
      docidentifier: a_ref.docidentifier,
      relation: [described_class.new(type: "updates", bibitem: b_ref)],
    )
    b = Relaton::Bib::ItemData.new(
      title: b_ref.title,
      docidentifier: b_ref.docidentifier,
      relation: [described_class.new(type: "updatedBy", bibitem: a_ref)],
    )

    round_a = Relaton::Bib::Item.from_yaml(a.to_yaml)
    round_b = Relaton::Bib::Item.from_yaml(b.to_yaml)

    expect(round_a.relation.first.type).to eq("updates")
    expect(round_a.relation.first.bibitem.docidentifier.first.content).to eq("ISO 2")
    expect(round_b.relation.first.type).to eq("updatedBy")
    expect(round_b.relation.first.bibitem.docidentifier.first.content).to eq("ISO 1")
  end
end
