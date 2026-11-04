# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      module Elements
        # Component part within a host (ISO 690 clause 7.4): host title
        # (emphasised), host editors, host edition, host place and
        # publisher. Host data comes from the typed partOf/includedIn
        # relation.
        class ComponentPart < Element
          HOST_RELATION_TYPES = %w[partOf includedIn].freeze

          def present?
            !host_title_text.empty?
          end

          def render
            "#{lead}#{host_title}#{host_editors}#{host_edition}" \
              "#{host_production}"
          end

          private

          def lead
            label = @i18n.label("in")
            label.empty? ? "" : "#{label} "
          end

          def relation
            Array(@model.relation).find do |r|
              HOST_RELATION_TYPES.include?(r.type)
            end
          end

          def host
            relation&.bibitem
          end

          def host_title_text
            return localized(relation&.description) if host.nil?

            titles_in_lang(host.title).map { |t| localized(t) }
              .join(" ").strip
          end

          def host_title
            return "" if host_title_text.empty?

            "#{@style.templates.title_open}#{host_title_text}" \
              "#{@style.templates.title_close}"
          end

          def host_editors
            eds = Array(host&.contributor).select { |c| has_role?(c, "editor") }
            names = eds.each_with_index
              .map { |c, i| host_person_name(c, first: i.zero?) }
              .reject(&:empty?)
            return "" if names.empty?

            " (#{@i18n.label(eds.one? ? 'ed' : 'eds')} #{join_names(names)})"
          end

          # ISO 690 clause 7.2 host editors: the first name inverted
          # (surname, initials), subsequent names in direct order, all in
          # mixed case
          def host_person_name(contributor, first:)
            person = contributor.person or return ""

            surname = person_surname(person)
            given = person_given(person)
            if first
              [surname, given].reject(&:empty?).join(", ")
            else
              [given, surname].reject(&:empty?).join(" ")
            end
          end

          def host_edition
            return "" if host.nil?

            edition = Edition.new(host, style: @style, i18n: @i18n,
                                  kind: item_kind)
            edition.present? ? ". #{edition.render}" : ""
          end

          def host_production
            return "" if host.nil?

            production = Production.new(host, style: @style, i18n: @i18n)
            production.present? ? ". #{production.render}" : ""
          end
        end
      end
    end
  end
end
