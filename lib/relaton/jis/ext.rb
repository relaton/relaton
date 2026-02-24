require_relative "doctype"

module Relaton
  module Jis
    class Ext < Iso::Ext
      attribute :schema_version, method: :get_schema_version
      attribute :doctype, Doctype

      def get_schema_version
        Relaton.schema_versions["relaton-model-jis"]
      end
    end
  end
end
