# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      module Elements
        # Medium designation (ISO 690 clause 7.5), bracketed per the
        # standard's worked examples, e.g. "[online]"
        class Medium < Element
          def present?
            !medium.empty?
          end

          def render
            medium
          end

          private

          def medium
            genre = @model.medium&.genre.to_s
            return genre.sub(/^\w/) { |c| c.upcase } unless genre.empty?

            key = "medium_#{@model.type}"
            label = @i18n.label(key)
            label == key ? "" : label
          end
        end
      end
    end
  end
end
