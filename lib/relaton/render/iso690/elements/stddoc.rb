# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      module Elements
        # Issuing body or status of a standard (ISO 690 clause 8.9): the
        # publisher or authorizer organization, falling back to the
        # capitalized status stage.
        class Stddoc < Element
          def present?
            !body.empty?
          end

          def render
            body
          end

          private

          def body
            orgs = %w[publisher authorizer].flat_map { |role|
              contributors(role).map { |c| org_plain(c) }
            }.reject(&:empty?)
            return orgs.join("; ") unless orgs.empty?

            stage = @model.status&.stage&.content.to_s
            stage.empty? ? "" : stage.sub(/^\w/) { |c| c.upcase }
          end

          # Issuing bodies render in mixed case, unlike creator organs
          def org_plain(contributor)
            Array(contributor.organization&.name)
              .map { |n| localized(n) }.join(", ")
          end
        end
      end
    end
  end
end
