# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      module Elements
        # Name(s) of creator(s) (ISO 690 clause 7.2). The first creator is
        # given inverted per the style's name form (SURNAME, forenames),
        # subsequent creators in direct order (forenames SURNAME); name
        # parts come from the typed model, never decomposed from a
        # rendered string.
        class Creator < Element
          def present?
            !creators.empty? || !fallback_name.empty?
          end

          def render
            return plain_render if @short

            joined = if (truncated = truncated_creators)
                       truncated
                     elsif creators.empty?
                       fallback_name
                     elsif (form = @style.templates.creators) && !form.empty?
                       ::Relaton::Render::Iso690::Template.new(form).evaluate(
                         "names" => Template::Field[true, join(names)],
                       )
                     else
                       join(names)
                     end
            case role_placement
            when "afterPeriod"
              # the in-slot trailing space separates the (eds.) marker
              # from the next element, which follows directly in the
              # template; a lone editor is unmarked unless declared
              if editors? && marked?
                "#{period(joined)}#{role_space}#{role_parenthesis} "
              else
                "#{period(joined)} "
              end
            else
              marker = editors? && marked? ? "#{role_space}#{role_parenthesis}" : ''
              "#{joined}#{marker}"
            end
          end

          # The short cite splits after the creators: they render as a
          # plain join, without the wrap and sentence period (1.x
          # short-cite templates carried no wrap)
          def plain_render
            marker = editors? && marked? ? "#{role_space}#{role_parenthesis}" : ''
            "#{join(names)}#{marker}"
          end

          # The editor role marker's parentheses follow the locale
          # (ASCII for Latin scripts, fullwidth for CJK)
          def role_parenthesis
            open = @i18n.punct_fetch("open-paren", "(")
            close = @i18n.punct_fetch("close-paren", ")")
            "#{open}#{role_word}#{close}"
          end

          # CJK cites the role marker tight against the name list
          def role_space
            @i18n.punct_fetch("marker-space", " ")
          end

          # The template-level role slot ("{{role}}"): the marker with
          # its locale spacing, when the creators are all editors
          def role_marker
            editors? ? "#{role_space}#{role_parenthesis}" : ""
          end

          def role_placement
            @style.scheme.name_form.role_placement || "glue"
          end

          def period(text)
            text.end_with?(".") ? text : "#{text}."
          end

          def marked?
            name_form.editors_marked &&
              (creators.size > 1 || name_form.lone_editor_marked)
          end

          def role_word
            @i18n.label(creators.one? ? "ed" : "eds")
          end

          # In-text (name-and-date) form: the principal creator only;
          # at the style's et-al threshold the cite truncates
          # ("Aluffi <em>et al.</em>")
          def in_text
            return in_text_etal if in_text_etal?

            name = creators.first ? in_text_name(creators.first) : ""
            etal? ? "#{name}#{etal_suffix}" : name
          end

          # The in-text cite truncates at its own threshold: at
          # inTextEtalCount creators it shows the first
          # inTextEtalDisplay surnames ("Aluffi <em>et al.</em>")
          def in_text_etal
            names = creators.first(name_form.in_text_etal_display)
              .map { |c| in_text_name(c) }
            "#{join(names)}#{etal_suffix}"
          end

          # The et-al suffix is the locale's label (roman by default; a
          # pack's `others` label may carry its own presentation), joined
          # per the style's list style — the serial comma before it is the
          # MLA form ("Fielding, Roy, et al.")
          def etal_suffix
            sep = name_form.list_style == "serial" ? "," : ""
            "#{sep} #{@i18n.label('others')}"
          end

          # The in-text cite names by surname alone (the 1.x
          # authorcitetemplate), never by initials
          def in_text_name(contributor)
            person = contributor.person or return org_name(contributor)
            complete = completename(person)
            return complete unless complete.nil?

            raw = surname(person).to_s
            name_form.surname_upcase ? raw.upcase : raw
          end

          def in_text_etal?
            count = name_form.in_text_etal_count
            count.positive? && creators.size >= count
          end

          def etal?
            count = name_form.etal_count
            count.positive? && creators.size >= count
          end

          # The principal creator's given names, as the name form declares
          def principal_given
            principal = creators.first or return ""
            person = principal.person or return ""
            complete = completename(person)
            return "" if complete

            given_names(person)
          end

          private

          def creators
            @creators ||= begin
              found = contributors("author")
              found = contributors("editor") if found.empty?
              found
            end
          end

          # The declared creator fallback for items with no personal
          # creators: the publishers' abbreviation or full name — all
          # publishers cite, joined per the style's list style ("ISO and
          # IEC")
          def fallback_name
            orgs = contributors("publisher")
            name = case name_form.creator_fallback
                   when "publisher_abbrev"
                     orgs.map do |c|
                       localized(c.organization&.abbreviation)
                     end
                   when "publisher_name"
                     orgs.map do |c|
                       localized(Array(c.organization&.name).first)
                     end
                   else
                     []
                   end
            join_names(name.reject(&:empty?))
          end

          def names
            creators.each_with_index
              .map do |contributor, index|
              format(contributor,
                     first: index.zero?)
            end
          end

          # The style's et-al truncation ("Aluffi, P., D. Anderson,
          # M. Hering <em>et al.</em>"): at etalCount creators, the
          # first etalDisplay names cite, comma-joined without the
          # terminal and-join
          def truncated_creators
            count = name_form.etal_count
            display = name_form.etal_display
            return nil if count <= 0 || display <= 0 ||
              creators.size < count

            creators.first(display).each_with_index
              .map do |contributor, index|
              format(contributor, first: index.zero?)
            end.join(", ") + etal_suffix
          end

          def format(contributor, first:)
            person = contributor.person or return org_name(contributor)
            name = completename_name(person, first: first) ||
              personal_name(person, first: first)
            name.empty? ? org_name(contributor) : name
          end

          def completename_name(person, first:)
            complete = completename(person) or return nil
            return complete unless name_form.completename_upcase

            first ? @style.render_name(surname: complete, given: "") :
              complete.upcase
          end

          def personal_name(person, first:)
            surname = surname(person).to_s
            given = given_names(person)
            if (first || name_form.inverted_all) && !name_form.given_name_first
              @style.render_name(surname: surname, given: given)
            else
              # the direct form initializes per the style's initials
              # knob ("S. Payne" over "Sam Payne")
              shown = name_form.subsequent_surname_upcase ? surname.upcase :
                        surname
              [person_given(person), shown].reject(&:empty?).join(" ")
            end
          end

          def name_form
            @style.scheme.name_form
          end

          def join(names)
            join_names(names)
          end

          def editors?
            !creators.empty? && creators.all? { |c| has_role?(c, "editor") }
          end

          def completename(person)
            value = person_completename(person)
            value.empty? ? nil : value
          end

          def surname(person)
            value = person_surname(person)
            value.empty? ? nil : value
          end

          def given_names(person)
            person_given(person)
          end

          def org_name(contributor)
            super
          end
        end
      end
    end
  end
end
