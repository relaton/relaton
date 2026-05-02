require_relative "structured_identifier"

module Relaton
  module Cen
    class Ext < Bib::Ext
      attribute :structuredidentifier, StructuredIdentifier, collection: true, initialize_empty: true

      def get_schema_version = Relaton.schema_versions["relaton-model-cen"]
    end
  end
end
