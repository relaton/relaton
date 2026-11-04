# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      module Elements
        # Physical size (ISO 690 clause 7.5, area): the model's typed
        # values render as "N unit" through the language pack; untyped
        # values pass through as written.
        class Size < Element
          def present?
            !values.empty?
          end

          def render
            values.map { |v| render_value(v) }.join(", ")
          end

          private

          def values
            Array(@model.size&.value)
          end

          def render_value(value)
            content = value.is_a?(String) ? value : value.content.to_s
            return content if content.empty? || value.is_a?(String)

            type = value.is_a?(Hash) ? value[:type] : value.type
            unit = type && @i18n.label("size_#{type}")
            return content if unit.nil? || unit == "size_#{type}"

            # A %-template places the value at its % (the extent
            # precedent: "% vol." cites "1 vol."); the value/unit glue
            # is otherwise locale-declared (CJK cites tight, "巻1"
            # over "vol. 1")
            return unit.gsub("%", content) if unit.include?("%")

            "#{unit}#{@i18n.punct_fetch('size-join', ' ')}#{content}"
          end
        end
      end
    end
  end
end
