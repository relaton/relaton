# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      module Elements
        # The authorizing body of a standard (the IETF RFC Series, the
        # W3C Recommendation process): the organization carrying the
        # authorizer role, cited after the status
        class Authorizer < Element
          def present?
            !authorizer_name.empty?
          end

          def render
            if (form = authorizer_form) && !form.empty?
              return Template.new(form).evaluate(
                "authorizer" => Template::Field[true, authorizer_name],
              )
            end

            authorizer_name
          end

          # The kind's declared form for this slot: the first entry of
          # the kind carrying one (a home variant may shadow the type)
          def authorizer_form
            kind = @style.kind_for(@model.type)
            @style.per_type.find do |t|
              t.type == kind && !t.authorizer.to_s.empty?
            end&.authorizer
          end

          private

          def authorizer_name
            contributors("authorizer").map do |c|
              Array(c.organization&.name).map { |n| localized(n) }.join(", ")
            end.reject(&:empty?).first.to_s
          end
        end
      end
    end
  end
end
