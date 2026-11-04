# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      module Elements
        # Production information: place and publisher (ISO 690 clause 7.8).
        # Place comes from the model's typed city; publishers from
        # organization contributors.
        class Production < Element
          def present?
            !places.empty? || !publishers.empty? || no_place_declared?
          end

          def render
            if (form = production_form) && !form.empty?
              return Template.new(form).evaluate(
                "production" => Template::Field[true, render_production],
              )
            end

            render_production
          end

          def render_production
            if publisher_first?
              return no_place_production_publisher_first if places.empty? &&
                no_place_declared?

              return [publishers.join("; "), places.map { |p| cjk_place(p) }]
                .reject(&:empty?).join(production_sep)
            end

            return no_place_production if places.empty? && no_place_declared?

            [places.map { |p| cjk_place(p) }, publishers.join("; ")]
              .reject(&:empty?).join(production_sep)
          end

          # A CJK locale's place names carry the CJK-Latin separator
        # ("Cambridge、UK" over "Cambridge, UK")
        def cjk_place(place)
          sep = @i18n.punct_fetch("cjk-latin-separator", "")
          sep.empty? ? place : place.gsub(", ", sep)
        end

        # The kind's declared form for this slot: the first entry of
        # the kind carrying one (a home variant may shadow the type)
        def production_form
          kind = @style.kind_for(@model.type)
          @style.per_type.find do |t|
            t.type == kind && !t.production.to_s.empty?
          end&.production
        end

        def publisher_first?
            @i18n.punct_fetch("production_order", "") == "publisher_first"
          end

          def production_sep
            @i18n.punct_fetch("production_sep", ": ")
          end

          def no_place_production_publisher_first
            label = @i18n.label("no_place")
            return "" if label.empty? || label == "no_place"

            pubs = publishers.join("; ")
            pubs.empty? ? label : "#{pubs}, #{label}"
          end

          # The no-place placeholder keeps the production separator even
          # when no publisher follows ("n.p.: n.d.")
          def no_place_production
            label = @i18n.label("no_place")
            return "" if label.empty? || label == "no_place"

            pubs = publishers.join("; ")
            pubs.empty? ? "#{label}#{production_sep}".rstrip :
              "#{label}#{production_sep}#{pubs}"
          end

          def no_place_declared?
            @style.type_template_for(item_kind)&.no_place == true
          end

          private

          def places
            Array(@model.place).map do |p|
              structured = [p.city.to_s, p.region.map(&:content),
                            p.country.map(&:content)]
                .flatten.reject { |c| c.strip.empty? }
              if structured.empty? && !p.formatted_place.to_s.empty?
                next p.formatted_place.to_s
              end

              structured.join(", ")
            end.reject(&:empty?)
          end

          def publishers
            contributors("publisher").map do |c|
              Array(c.organization&.name).map { |n| localized(n) }.join(", ")
            end.reject(&:empty?)
          end
        end
      end
    end
  end
end
