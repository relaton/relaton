require_relative "doctype"

module Relaton
  module Ieee
    class Ext < Lutaml::Model::Serializable
      attribute :schema_version, method: :get_schema_version
      attribute :doctype, Doctype
      attribute :subdoctype, :string, values: %w[amendment corrigendum erratum]
      attribute :flavor, :string
      attribute :trial_use, :boolean
      attribute :ics, Bib::ICS, collection: true
      attribute :standard_status, :string, values: %w[Inactive Active Superseded]
      attribute :standard_modified, :string, values: %w[Draft Withdrawn Superseded Superseded Reserved Redline]
      attribute :pubstatus, :string, values: %w[Active Inactive]
      attribute :holdstatus, :string, values: %w[Hold Publish]
      attribute :program, :string

      xml do
        map_attribute "schema-version", to: :schema_version
        map_element "doctype", to: :doctype
        map_element "subdoctype", to: :subdoctype
        map_element "flavor", to: :flavor
        map_element "trial-use", to: :trial_use
        map_element "ics", to: :ics
        map_element "standard_status", to: :standard_status
        map_element "standard_modified", to: :standard_modified
        map_element "pubstatus", to: :pubstatus
        map_element "holdstatus", to: :holdstatus
        map_element "program", to: :program
      end

      def get_schema_version
        Relaton.schema_versions["relaton-model-ieee"]
      end
    end
  end
end
