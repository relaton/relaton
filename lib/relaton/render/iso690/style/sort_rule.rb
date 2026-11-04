# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      class Style
        # SortRule: one ordering key of a bibliographic index sort
        # (relaton-models SortRule).
        class SortRule < Lutaml::Model::Serializable
          attribute :attribute, :string
          attribute :order, :string

          key_value do
            map "attribute", to: :attribute
            map "order", to: :order
          end

          def descending?
            order == "descending"
          end
        end
      end
    end
  end
end
