module Relaton
  module Jcgm
    # A single structured identifier (e.g. `{ docnumber: "17" }`). JCGM records
    # carry this as a single mapping, not a sequence, so it overrides the base
    # `Bib::Ext#structuredidentifier` collection (mirrors BIPM's model).
    class StructuredIdentifier < Lutaml::Model::Serializable
      attribute :docnumber, :string
      attribute :part, :string
      attribute :appendix, :string

      xml do
        map_element "docnumber", to: :docnumber
        map_element "part", to: :part
        map_element "appendix", to: :appendix
      end
    end
  end
end
