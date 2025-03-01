require_relative "doctype"

module Relaton
  module Oasis
    class Ext < Lutaml::Model::Serializable
      attribute :schema_version, :string
      attribute :doctype, Doctype
      attribute :subdoctype, :string
      attribute :editorialgroup, Bib::EditorialGroup
      attribute :ics, Bib::ICS, collection: true
      attribute :structuredidentifier, Bib::StructuredIdentifier, collection: true
      attribute :technology_area, :string, collection: true, values: %w[
        Cloud Content-Technologies Cybersecurity e-Business eGov/Legal Emergency-Management
        Energy Information-Modeling IoT Lifecycle-Integration Localization Messaging
        Privacy/Identity Security SOA Web-Services Software-Development Virtualization
      ]

      xml do
        map_attribute "schema-version", to: :schema_version
        map_element "doctype", to: :doctype
        map_element "subdoctype", to: :subdoctype
        map_element "editorialgroup", to: :editorialgroup
        map_element "ics", to: :ics
        map_element "structuredidentifier", to: :structuredidentifier
        map_element "technology-area", to: :technology_area
      end
    end
  end
end
