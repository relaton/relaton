require_relative "doctype"

module Relaton
  module Iala
    # IALA bibliographic item extension. Adds IALA-specific structured
    # metadata on top of the shared Relaton::Bib::Ext so the fields
    # round-trip through both XML and YAML without per-repo merge hacks.
    class Ext < Bib::Ext
      attribute :doctype, Doctype
      attribute :urn,        :string
      attribute :webpage,    :string
      attribute :committee,  :string
      attribute :normative,  :string
      attribute :supersedes, :string, collection: true, initialize_empty: true

      xml do
        map_element "urn",        to: :urn
        map_element "webpage",    to: :webpage
        map_element "committee",  to: :committee
        map_element "normative",  to: :normative
        map_element "supersedes", to: :supersedes
      end

      key_value do
        map_element "urn",        to: :urn
        map_element "webpage",    to: :webpage
        map_element "committee",  to: :committee
        map_element "normative",  to: :normative
        map_element "supersedes", to: :supersedes
      end
    end
  end
end
