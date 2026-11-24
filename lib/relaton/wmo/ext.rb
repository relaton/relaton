module Relaton
  module Wmo
    # WMO bibliographic item extension. Adds WMO-specific structured
    # metadata on top of the shared Relaton::Bib::Ext so the fields
    # round-trip through both XML and YAML without per-repo merge hacks.
    # Doctype is referenced lazily via autoload from lib/relaton/wmo.rb.
    class Ext < Bib::Ext
      attribute :doctype, :string
      attribute :urn,     :string
      attribute :webpage, :string

      xml do
        map_element "urn",     to: :urn
        map_element "webpage", to: :webpage
      end

      key_value do
        map_element "urn",     to: :urn
        map_element "webpage", to: :webpage
      end
    end
  end
end
