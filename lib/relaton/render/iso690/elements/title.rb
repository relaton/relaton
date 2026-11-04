# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      module Elements
        # Title of the resource (ISO 690 clause 7.3), emphasised by the
        # style's declared title markers
        class Title < Element
          def present?
            !main_title.empty?
          end

          # The citation capsule's plain title (the 1.x citetemplate's
          # "{{ title }}"): the same resolution, no style markers
          def plain
            main_title
          end

          def render
            text = main_title
            return text if analytic? && @short
            if !@short &&
               (form = @style.title_form_for(@style.kind_for(@model.type)))
              # the kind's own form carries the whole emphasis
              return ::Relaton::Render::Iso690::Template.new(form)
                .evaluate("title" => Template::Field[!text.empty?, text])
            end

            "#{@style.templates.title_open}#{text}" \
              "#{@style.templates.title_close}"
          end

          private

          # ISO 690: analytic titles are not emphasised; the host or
          # serial carries the emphasis
          def analytic?
            %w[component_part serial_part]
              .include?(@style.kind_for(@model.type))
          end

          # A typed main title wins; an untyped title is main by
          # default, but yields to a typed one
          def main_title
            titles = Array(@model.title)
            mains = titles.select { |x| x.type == "main" }
            mains = titles.select { |x| x.type.nil? } if mains.empty?
            mains = titles if mains.empty?
            localized(titles_in_lang(mains).first)
          end
        end
      end
    end
  end
end
