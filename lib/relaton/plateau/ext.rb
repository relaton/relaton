require_relative "doctype"

module Relaton
  module Plateau
    class Ext < Bib::Ext
      attribute :doctype, Doctype
      attribute :stagename, Iso::Stagename
      attribute :filesize, :integer

      xml do
        map_element "stagename", to: :stagename
        map_element "filesize", to: :filesize
      end

      key_value do
        map_element "stagename", to: :stagename
        map_element "filesize", to: :filesize
      end

      def get_schema_version = Relaton.schema_versions["relaton-model-plateau"]
    end
  end
end
