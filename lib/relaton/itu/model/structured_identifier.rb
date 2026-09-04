module Relaton
  module Itu
    class StructuredIdentifier < Lutaml::Model::Serializable
      attribute :bureau, :string, values: %w[T D R]
      attribute :docnumber, :string
      attribute :annexid, :string
      attribute :amendment, :integer
      attribute :corrigendum, :integer

      xml do
        map_element "bureau", to: :bureau
        map_element "docnumber", to: :docnumber
        map_element "annexid", to: :annexid
        map_element "amendment", to: :amendment
        map_element "corrigendum", to: :corrigendum
      end

      # `Bib::ItemData#ext_to_all_parts!` / `#ext_remove_date` broadcast to
      # `ext.structuredidentifier` as well as to `docidentifier`. This class
      # descends from `Lutaml::Model::Serializable` rather than
      # `Bib::StructuredIdentifier`, so it does not inherit that class's no-op
      # defaults and the broadcast raised `NoMethodError` on every ITU item.
      #
      # ITU structured identifiers model neither a part nor a date: `bureau`,
      # `docnumber`, `annexid`, `amendment` and `corrigendum` are all identity,
      # and stripping any of them would name a different document. The date is
      # handled by `Relaton::Itu::Docidentifier#remove_date!`, which strips the
      # `(MM/YYYY)` suffix from the rendered string. So all three are no-ops.

      def remove_part!; end

      def remove_date!; end

      def to_all_parts!; end
    end
  end
end
