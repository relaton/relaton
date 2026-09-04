module Relaton
  module Bipm
    class StructuredIdentifier < Lutaml::Model::Serializable
      attribute :docnumber, :string
      attribute :part, :string
      attribute :appendix, :string

      xml do
        map_element "docnumber", to: :docnumber
        map_element "part", to: :part
        map_element "appendix", to: :appendix
      end

      # `Bib::ItemData#ext_to_all_parts!` / `#ext_remove_date` broadcast to
      # `ext.structuredidentifier` as well as to `docidentifier`. This class
      # descends from `Lutaml::Model::Serializable` rather than
      # `Bib::StructuredIdentifier` (BIPM stores a single mapping, not a
      # sequence), so it does not inherit that class's no-op defaults and the
      # broadcast raised `NoMethodError` on every BIPM item.
      #
      # BIPM structured identifiers carry no date, so `remove_date!` has nothing
      # to strip; the year lives on the docidentifier. `part` is real and is
      # cleared. (Identical to `Relaton::Jcgm::StructuredIdentifier`.)

      def remove_part!
        self.part = nil
      end

      def remove_date!; end

      def to_all_parts!
        remove_part!
      end
    end
  end
end
