require_relative "doctype"

module Relaton
  module Jis
    class Ext < Lutaml::Model::Serializable
      attribute :schema_version, :string
      attribute :doctype, Doctype
      attribute :editorialgroup, Iso::ISOProjectGroup
      attribute :flavor, :string
      attribute :ics, Bib::ICS, collection: true
      attribute :structuredidentifier, Iso::StructuredIdentifier
      attribute :stagename, Iso::Stagename

      xml do
        map_attribute "schema-version", to: :schema_version
        map_element "doctype", to: :doctype
        map_element "editorialgroup", to: :editorialgroup
        map_element "flavor", to: :flavor
        map_element "ics", to: :ics
        map_element "structuredidentifier", to: :structuredidentifier
        map_element "stagename", to: :stagename
      end
    end
  end
end
