# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      module Elements
        # The item's status stage, capitalized, parenthesized beside
        # the identifier ("OGC 05-020r27 (Draft)"); published statuses
        # are not cited
        class Status < Element
          def present?
            !stage.empty? &&
              !%w[published retired].include?(stage.downcase)
          end

          def render
            " (#{stage})"
          end

          private

          def stage
            raw = @model.status&.stage&.content.to_s
            raw.empty? ? "" : raw.sub(/^\w/) { |c| c.upcase }
          end
        end
      end
    end
  end
end
