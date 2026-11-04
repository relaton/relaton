# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      module Elements
        # The item's updated date, nested in the creator date group
        # ("(2018 (updated November 2018))")
        class Updated < Element
          def present?
            !render.empty?
          end

          def render
            d = Array(@model.date).find { |x| x.type == "updated" } or
              return ""
            value = d.at || d.from || d.to or return ""

            date = value.to_date
            " (#{label('updated')} #{month(date.month)} #{date.year})"
          rescue ArgumentError, TypeError
            ""
          end

          private

          def label(key)
            @i18n.label(key)
          end

          def month(num)
            @i18n.label("month_#{num}")
          end
        end
      end
    end
  end
end
