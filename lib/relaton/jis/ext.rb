require_relative "doctype"
require_relative "structured_identifier"

module Relaton
  module Jis
    class Ext < Iso::Ext
      attribute :doctype, Doctype
      attribute :structuredidentifier, StructuredIdentifier

      def get_schema_version = Relaton.schema_versions["relaton-model-jis"]
    end
  end
end
