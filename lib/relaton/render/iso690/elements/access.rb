# frozen_string_literal: true

require "date"

module Relaton
  module Render
    module Iso690
      module Elements
        # Date of access (ISO 690 clause 7.12): "[viewed: September 3,
        # 2019]" for online resources consulted.
        class Access < Element
          def present?
            !date_text.empty?
          end

          def render
            "[#{@i18n.label('viewed')}: #{date_text}]"
          end

          private

          def date_text
            d = Array(@model.date).find { |x| x.type == "accessed" } or return ""
            value = (d.at || d.from || d.to).to_s
            parts = value.split("-")
            case parts.size
            when 3
              date = ::Date.parse(value)
              "#{month(date.month)} #{date.day}, #{date.year}"
            when 2
              "#{month(parts[1].to_i)} #{parts[0]}"
            else
              value
            end
          end

          def month(num)
            @i18n.label("month_#{num}")
          end
        end
      end
    end
  end
end
