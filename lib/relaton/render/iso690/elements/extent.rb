# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      module Elements
        # Extent of the item (ISO 690 clause 7.11): page localities.
        class Extent < Element
          def present?
            !render.empty?
          end

          def render
            groups = [numeration, page_range].reject { |g| g.empty? }
            groups.join(group_sep)
          end

          private

          # An extent label is a template over its value: "vol. %" in
          # the Latin pack, "巻%" / "%頁" in the CJK packs
          def unit(type, value)
            label = @i18n.label(type)
            return "#{label} #{value}" unless label.include?("%")

            label.sub("%", value)
          end

          def cjk?(label)
            label.match?(/\p{Han}|\p{Hiragana}|\p{Katakana}/)
          end

          def group_sep
            sep = @i18n.label("extent_group_separator")
            return sep unless sep == "extent_group_separator"

            cjk?(@i18n.label("page")) ? "、 " : ", "
          end

          def numeration
            %w[volume issue].filter_map do |type|
              loc = localities.find { |l| l.type == type }
              next if loc.nil? || loc.reference_from.to_s.empty?

              unit(type, loc.reference_from)
            end.join(" ")
          end

          def page_range
            loc = localities.find { |l| l.type == "page" } or return ""
            from = loc.reference_from.to_s
            to = loc.reference_to.to_s
            if to.empty? || to == from
              unit("page", from)
            else
              range = "#{from}#{@i18n.label('date_range')}#{to}"
              unit("pages", range)
            end
          end

          def localities
            Array(@model.extent).flat_map do |e|
              Array(e.locality) +
                Array(e.locality_stack).flat_map { |s| Array(s.locality) }
            end
          end
        end
      end
    end
  end
end
