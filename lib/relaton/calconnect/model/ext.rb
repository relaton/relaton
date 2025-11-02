require_relative "doctype"

module Relaton
  module Calconnect
    class Ext < Lutaml::Model::Serializable
      attribute :schema_version, method: :get_schema_version
      attribute :doctype, Doctype
      attribute :subdoctype, :string
      attribute :flavor, :string
      attribute :ics, Bib::ICS, collection: true

      xml do
        map_attribute "schema-version", to: :schema_version
        map_element "doctype", to: :doctype
        map_element "subdoctype", to: :subdoctype
        map_element "flavor", to: :flavor
        map_element "ics", to: :ics
      end

      def get_schema_version
        Relaton.schema_versions["relaton-model-cc"]
      end
    end
  end
end
