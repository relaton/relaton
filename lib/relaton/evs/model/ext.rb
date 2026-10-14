require_relative "structured_identifier"

module Relaton
  module Evs
    class Ext < Bib::Ext
      attribute :structuredidentifier, StructuredIdentifier, collection: true, initialize_empty: true

      # No `relaton-model-evs` gem exists yet, so the schema version stays the
      # `Bib::Ext` default (nil), like the other model-less flavors.
    end
  end
end
