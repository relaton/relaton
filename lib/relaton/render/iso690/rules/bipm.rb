# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      module Rules
        # The BIPM rule set, moved verbatim from the metanorma-bipm
        # flavor's BipmElements: the affiliation-free organization
        # creator, the bold-volume journal numeration, the
        # no-place-with-publisher production, the separator-carrying
        # edition and medium, and the component-part host order.
        # Select from pack data:
        #   rules: { creator: bipm_creator, ... }
        module Bipm
          # The BIPM component-part order: the host editors before the
          # host title, the host medium after it, and the production
          # parenthesized with its own trailing period
          class BipmComponentPart < Elements::ComponentPart
            def render
              h = host or return ""
              out = +"#{lead}#{host_names(h)} (#{eds_label(h)})"
              out += " #{host_title}" unless host_title_text.empty?
              out += medium_text(h)
              out += production_text(h)
              out
            end

            private

            def host_editors(h)
              Array(h.contributor).select { |c| has_role?(c, "editor") }
            end

            def eds_label(h)
              @i18n.label(host_editors(h).one? ? "ed" : "eds")
            end

            def host_names(h)
              names = host_editors(h).map { |c|
                person = c.person or next ""

                [person_surname(person), person_given(person)].reject(&:empty?)
                  .join(" ")
              }.reject(&:empty?)
              join_names(names)
            end

            def medium_text(h)
              BipmMedium.new(h, style: @style, i18n: @i18n).render.to_s
            end

            def production_text(h)
              production = Elements::Production
                .new(h, style: @style, i18n: @i18n).render.to_s
              production.empty? ? "" : " (#{production})."
            end
          end

          # The BIPM journal numeration: the volume bold and the issue
          # in parens, pages unlabelled. Separate extent elements join
          # with semicolons, localities within one element with spaces
          class BipmExtent < Elements::Extent
            def render
              groups = extent_locality_groups.map { |g| group_text(g) }
                .reject(&:empty?)
              groups.join("; ")
            end

            private

            def extent_locality_groups
              Array(@model.extent).map do |e|
                Array(e.locality) +
                  Array(e.locality_stack).flat_map { |s| Array(s.locality) }
              end
            end

            def group_text(localities)
              volume = plain_locality(localities, "volume")
              volume = volume.empty? ? "" : "<strong>#{volume}</strong>"
              issue = plain_locality(localities, "issue")
              issue = issue.empty? ? "" : "(#{issue})"
              [volume, issue, page_text(localities)].reject(&:empty?).join(" ")
            end

            def plain_locality(localities, type)
              loc = localities.find { |l| l.type == type } or return ""
              loc.reference_from.to_s
            end

            def page_text(localities)
              loc = localities.find { |l| l.type == "page" } or return ""
              from = loc.reference_from.to_s
              to = loc.reference_to.to_s
              text = to.empty? || to == from ? from :
                "#{from}#{@i18n.label('date_range')}#{to}"
              return text if item_kind == "serial_part"

              label = @i18n.label(to.empty? || to == from ? "page" : "pages")
              # the page labels are %-templates ("pp. %"); the block
              # form keeps a % in the cited text from re-expanding
              label.include?("%") ? label.gsub("%") { text } : "#{label} #{text}"
            end
          end

          # The BIPM production: the no-place placeholder stands only
          # with a publisher ("(n.p.: Publisher)"); a nameless
          # publisher drops the production entirely
          class BipmProduction < Elements::Production
            private

            def no_place_production
              return "" if publishers.empty?

              super
            end
          end

          # The serial volume, bold, from the size's volume value
          class BipmVolume < Element
            def present?
              !render.empty?
            end

            def render
              volume = Array(@model.size&.value).find do |v|
                !v.is_a?(String) && !v.is_a?(Hash) && v.type == "volume"
              end or return ""

              "<strong>#{volume.content}</strong>"
            end
          end

          # The BIPM medium, verbatim and bracketed with its leading
          # separator (" [Online]", " [dataset]") — an absent medium
          # attaches to nothing
          class BipmMedium < Elements::Medium
            private

            def medium
              m = @model.medium or return ""
              text = m.carrier.to_s
              text = m.genre.to_s if text.empty?
              text = [m.form.to_s, m.size.to_s].reject(&:empty?)
                .join(", ") if text.empty?
              text.empty? ? "" : " [#{text}]"
            end
          end

          # The BIPM edition carries its own leading separator (",
          # First edition" for monographs, ". Version 2" online), so
          # its absence drops the separator with it
          class BipmEdition < Elements::Edition
            def render
              text = super.to_s
              sep = item_kind == "monograph" ? ", " : ". "
              text.empty? ? "" : "#{sep}#{text}"
            end
          end

          # The BIPM organization creator: the name alone, no
          # abbreviation suffix. Standards without personal creators
          # cite their publisher's name; monographs cite nothing
          class BipmCreator < Elements::Creator
            private

            def org_name(contributor)
              Array(contributor.organization&.name).map { |n| localized(n) }
                .join(", ")
            end

            def fallback_name
              return "" if %w[monograph continuing component_part]
                .include?(@style.kind_for(@model.type))

              publishers = contributors("publisher").filter_map do |c|
                localized(Array(c.organization&.name).first)
              end
              publishers.reject(&:empty?).first.to_s
            end
          end
        end
      end
    end
  end
end
