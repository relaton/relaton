require_relative "doctype"

module Relaton
  module Oasis
    class Ext < Bib::Ext
      attribute :doctype, Doctype
      attribute :technology_area, :string, collection: true, values: %w[
        Cloud Content-Technologies Cybersecurity e-Business eGov/Legal Emergency-Management
        Energy Information-Modeling IoT Lifecycle-Integration Localization Messaging
        Privacy/Identity Security SOA Web-Services Software-Development Virtualization
      ]

      xml { map_element "technology-area", to: :technology_area }
      key_value { map "technology_area", to: :technology_area }

      def get_schema_version = Relaton.schema_versions["relaton-model-oasis"]
    end
  end
end
