# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      # Base data element (ISO 690 clause 7). An element wraps typed data
      # taken from the relaton model instance; #present? is the omission
      # predicate, #render the element's formatting method. Punctuation
      # between elements belongs to the kind/style, not the element.
      class Element
        def initialize(model, style:, i18n:, kind: nil, short: false)
          @model = model
          @style = style
          @i18n = i18n
          @kind = kind
          @short = short
        end

        def present?
          false
        end

        def render
          nil
        end

        private

        def localized(value)
          value&.content.to_s
        end

        # Localizable values scoped to the render language: the variants
        # declared in that language, or all of them when none matches
        def titles_in_lang(values)
          titles = Array(values)
          in_lang = titles.select { |t| Array(t.language).include?(@i18n.lang) }
          in_lang.empty? ? titles : in_lang
        end

        def contributors(role)
          Array(@model.contributor).select { |c| has_role?(c, role) }
        end

        def has_role?(contributor, role)
          Array(contributor.role).any? do |r|
            r.is_a?(String) ? r == role : r.type == role
          end
        end

        def org_name(contributor)
          shown = ->(n) do
            text = localized(n)
            @style.scheme.name_form.org_upcase ? text.upcase : text
          end
          name = Array(contributor.organization&.name)
            .map(&shown).join(", ")
          abbrev = localized(contributor.organization&.abbreviation)
          return name if name.empty? || abbrev.empty?

          "#{name} (#{abbrev})"
        end

        def item_kind
          @kind || @style.kind_for(@model.type)
        end

        def person_completename(person)
          localized(person.name&.completename)
        end

        def person_surname(person)
          localized(person.name&.surname)
        end

        def person_given(person)
          parts = Array(person.name&.forename).map do |f|
            content = localized(f)
            next content unless content.empty?
            next initial(f.initial) if f.initial.to_s.length == 1

            ""
          end.reject(&:empty?)
          sep = @style.scheme.name_form.initials_separator.to_s
          return reinitials(localized(person.name&.formatted_initials)) if
            parts.empty?
          return given_with_first_full(parts, sep) if initials?

          parts.join(" ")
        end

        # The document-history name form: the first forename cites in
        # full, the rest as initials ("Milena S.")
        def given_with_first_full(parts, sep)
          initials = parts.map { |p| initial(p) }
          return initials.join(sep) unless
            @style.scheme.name_form.subsequent_initials

          rest = parts.drop(1).map { |p| initial(p) }.join(sep)
          rest.empty? ? parts.first : "#{parts.first}#{sep}#{rest}"
        end

        # Declared initials are a list in string form; rejoin them with
        # the style's separator
        def reinitials(raw)
          sep = @style.scheme.name_form.initials_separator.to_s
          dots = @style.scheme.name_form.initials_period
          raw.split(/\s+/).reject(&:empty?).map { |i| dots ? i : i.delete(".") }
            .join(sep)
        end

        def initial(name)
          @style.scheme.name_form.initials_period ? "#{name[0]}." : name[0]
        end

        def initials?
          @style.scheme.name_form.initials
        end

        def join_names(names)
          # A style with no join word renders a plain serial list,
          # separated per the locale (the comma, or the CJK 、)
          if @i18n.label("and").empty? && names.size > 1
            sep = @i18n.label("list_separator")
            sep = ", " if sep == "list_separator"
            return names.join(sep)
          end

          oxford = @i18n.label("oxford_comma")
          if serial_list? && names.size > 1 && !oxford.empty?
            return "#{names[0..-2].join(', ')}#{oxford} " \
              "#{@i18n.label('and')} #{names.last}"
          end

          case names.size
          when 0 then ""
          when 1 then names.first
          when 2 then names.join(" #{@i18n.label('and')} ")
          else
            "#{names[0..-2].join(', ')}#{oxford} " \
            "#{@i18n.label('and')} #{names.last}"
          end
        end

        # Serial list style: the oxford comma appears at every gap of a
        # name list, including between two names
        def serial_list?
          @style.scheme.name_form.list_style == "serial"
        end
      end
    end
  end
end
