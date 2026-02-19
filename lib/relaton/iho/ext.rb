require_relative "doctype"
require_relative "comment_period"

module Relaton
  module Iho
    class Ext < Bib::Ext
      attribute :doctype, Doctype
      attribute :commentperiod, CommentPeriod

      xml do
        map_element "commentperiod", to: :commentperiod
      end

      def schema_version
        Relaton.schema_versions["relaton-model-iho"]
      end
    end
  end
end
