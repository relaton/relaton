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

      # `Bib::ItemData#ext_to_all_parts!` / `#ext_remove_date` broadcast to
      # `ext.structuredidentifier` just as they do to `docidentifier`, so these
      # three are as required here as on the docidentifier. This class descends
      # from `Lutaml::Model::Serializable` rather than `Bib::StructuredIdentifier`
      # (JCGM stores a single mapping, not a sequence), so the methods were not
      # merely unimplemented — they were absent, and the broadcast raised
      # `NoMethodError` on every JCGM item.
      #
      # JCGM structured identifiers carry no date field, so `remove_date!` has
      # nothing to strip and is a deliberate no-op; the year lives on the
      # docidentifier's pubid, which `Docidentifier#remove_date!` handles.

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
