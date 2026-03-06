require_relative "doctype"

module Relaton
  module Calconnect
    class Ext < Bib::Ext
      attribute :schema_version, method: :get_schema_version
      attribute :doctype, Doctype
      attribute :subdoctype, :string
      attribute :flavor, :string

      def get_schema_version
        Relaton.schema_versions["relaton-model-cc"]
      end
    end
  end
end
