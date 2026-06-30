require_relative "doctype"

module Relaton
  module Oiml
    # OIML bibliographic item extension. Adds the OIML-specific structured
    # metadata (relaton/relaton-oiml#2) on top of the shared Relaton::Bib::Ext.
    # These fields are populated on the enhanced OIML Recommendations and are
    # absent on most records; they round-trip through both XML and YAML.
    class Ext < Bib::Ext
      attribute :doctype, Doctype
      attribute :scope, :string
      attribute :quantity, :string
      attribute :measuring_instrument, :string
      attribute :focus_area, :string
      attribute :sustainability_framework, :string
      attribute :doi, :string

      xml do
        map_element "scope", to: :scope
        map_element "quantity", to: :quantity
        map_element "measuring_instrument", to: :measuring_instrument
        map_element "focus_area", to: :focus_area
        map_element "sustainability_framework", to: :sustainability_framework
        map_element "doi", to: :doi
      end

      key_value do
        map_element "scope", to: :scope
        map_element "quantity", to: :quantity
        map_element "measuring_instrument", to: :measuring_instrument
        map_element "focus_area", to: :focus_area
        map_element "sustainability_framework", to: :sustainability_framework
        map_element "doi", to: :doi
      end

      # No dedicated OIML (flavor) model exists yet, so the extension reuses the
      # base Relaton::Bib behaviour and does not advertise a flavor-specific
      # schema version. Add a `relaton-model-oiml` entry to relaton-bib's
      # versions.json and override #schema_version here once that model lands.
    end
  end
end
