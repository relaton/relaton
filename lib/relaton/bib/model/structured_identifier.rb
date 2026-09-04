module Relaton
  module Bib
    class StructuredIdentifier < Lutaml::Model::Serializable
      attribute :type, :string
      attribute :agency, :string, collection: (1..)
      attribute :klass, :string
      attribute :docnumber, :string
      attribute :partnumber, :string
      attribute :edition, :string
      attribute :version, :string
      attribute :supplementtype, :string
      attribute :supplementnumber, :string
      attribute :amendment, :string
      attribute :corrigendum, :string
      attribute :language, :string
      attribute :year, :string

      xml do
        root "structuredidentifier"
        map_attribute "type", to: :type
        map_element "agency", to: :agency
        map_element "class", to: :klass
        map_element "docnumber", to: :docnumber
        map_element "partnumber", to: :partnumber
        map_element "edition", to: :edition
        map_element "version", to: :version
        map_element "supplementtype", to: :supplementtype
        map_element "supplementnumber", to: :supplementnumber
        map_element "amendment", to: :amendment
        map_element "corrigendum", to: :corrigendum
        map_element "language", to: :language
        map_element "year", to: :year
      end

      # The same broadcast reaches `ext.structuredidentifier`
      # (`Bib::ItemData#ext_to_all_parts!` / `#ext_remove_date`), so these
      # default to no-ops for the same reason as `Bib::Docidentifier`'s: a
      # structured identifier with no part and no date has nothing to strip.
      # Flavors that model one override them — see
      # `Relaton::Iso::StructuredIdentifier` and `Relaton::Gb::StructuredIdentifier`.

      def remove_part!; end

      def to_all_parts!; end

      def remove_date!; end
    end
  end
end
