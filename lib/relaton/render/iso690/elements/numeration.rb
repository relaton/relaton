# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      module Elements
        # Numeration within a series (ISO 690 clause 7.9): report numbers
        class Numeration < Element
          def present?
            !docnumber.to_s.empty?
          end

          def render
            "#{@i18n.label('report_no')} #{docnumber}"
          end

          private

          def docnumber
            @model.docnumber
          end
        end
      end
    end
  end
end
