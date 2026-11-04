# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      module Elements
        # Date of publication (ISO 690 clause 7.7). The relaton model
        # provides typed date values (StringDate::Value#to_date); years
        # come from the model, never from string manipulation. A from/to
        # pair renders as a range (closed or open).
        class PubDate < Element
          def present?
            !render.nil?
          end

          def render
            range || year&.to_s
          end

          private

          def publication_date
            Array(@model.date).find(&:published) ||
              Array(@model.date).find { |d| d.type.nil? } ||
              Array(@model.date).find { |d| d.type == "created" } ||
              Array(@model.date).find { |d| d.type == "issued" } ||
              Array(@model.date).find { |d| d.type == "circulated" }
          end

          def publication_date_value
            d = publication_date or return nil
            d.from || d.at || d.to
          end

          def range
            d = publication_date or return nil
            dash = @i18n.label("date_range")
            if d.from && d.to
              fy = d.from.to_date.year
              ty = d.to.to_date.year
              return (fy == ty ? fy.to_s : "#{fy}#{dash}#{ty}")
            end

            # A from-only date is an open run ("1925–") for a
            # continuing resource; a monograph's publication date
            # cites the year bare ("2022") — the trailing dash would
            # leak into the terminator otherwise
            if d.from && %w[continuing serial_part online webdoc]
                .include?(item_kind)
              "#{d.from.to_date.year}#{dash}"
            end
          end

          def year
            publication_date_value.to_date.year
          rescue ArgumentError, TypeError, NoMethodError
            nil
          end
        end
      end
    end
  end
end
