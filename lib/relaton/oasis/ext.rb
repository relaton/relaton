require_relative "doctype"

module Relaton
  module Oasis
    class Ext < Bib::Ext
      attribute :schema_version, method: :get_schema_version
      attribute :doctype, Doctype
      attribute :technology_area, :string, collection: true, values: %w[
        Cloud Content-Technologies Cybersecurity e-Business eGov/Legal Emergency-Management
        Energy Information-Modeling IoT Lifecycle-Integration Localization Messaging
        Privacy/Identity Security SOA Web-Services Software-Development Virtualization
      ]

      xml do
        map_element "technology-area", to: :technology_area
      end

      def get_schema_version
        Relaton.schema_versions["relaton-model-oasis"]
      end
    end
  end
end
