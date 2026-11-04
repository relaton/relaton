# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      module Elements
        # Series title and number (ISO 690 clause 7.10)
        class Series < Element
          def present?
            !series_title.empty?
          end

          def render
            if (form = series_form) && !form.empty?
              return ::Relaton::Render::Iso690::Template.new(form).evaluate(
                "seriestitle" => Template::Field[!series_title.empty?,
                                                 series_title],
                "seriesnumber" => Template::Field[!number.empty?, number],
                "seriesrun" => Template::Field[!run.empty?, run],
              )
            end

            base = "#{@style.templates.title_open}#{series_title}" \
                   "#{@style.templates.title_close}"
            if number.empty?
              base
            else
              # an empty series_no label joins on the space alone (the
              # CJK form: "Series 472")
              label = @i18n.label("series_no")
              label.empty? ? "#{base} #{number}" :
                "#{base}, #{label} #{number}"
            end
          end

          private

          def series
            Array(@model.series).first
          end

          def series_title
            titles_in_lang(series&.title).map { |t| localized(t) }
              .join(" ").strip
          end

          def number
            series&.number.to_s
          end

          def run
            series&.run.to_s
          end

          # The style's series form for this item's resource kind, falling
          # back to the style-wide form
          def series_form
            variant = @style.per_type
              .find { |t| t.type == @style.kind_for(@model.type) }
            variant&.series || @style.templates.series
          end
        end
      end
    end
  end
end
