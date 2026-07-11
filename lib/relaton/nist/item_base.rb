require_relative "docidentifier"

module Relaton
  module Nist
    # Nested bibitem used inside Relation. Mirrors Iso::ItemBase / Iec::ItemBase:
    # overrides the shared docidentifier/relation with the NIST-flavored types so
    # a relation's cross-reference ids are Nist::Docidentifier too (keeping the
    # whole tree's docidentifier collections a single, YAML-serializable type).
    class ItemBase < Bib::ItemBase
      model ItemData

      attribute :docidentifier, Docidentifier, collection: true, initialize_empty: true
      attribute :relation, Relation, collection: true, initialize_empty: true
    end
  end
end
