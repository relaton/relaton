# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      module Elements
        # Edition and version (ISO 690 clause 7.6). The model numbers the
        # edition through Edition#number (falling back to its content).
        class Edition < Element
          def present?
            !raw.to_s.empty?
          end

          def render
            return "#{@i18n.label('version')} #{raw}" unless word_edition?

            # The exact worded forms first ("first edition", "第1版"),
            # then the generic ordinal template, the cardinal last: a
            # specific label outranks a template that would apply to
            # any number
            word = @i18n.label("edition_#{number}")
            return word unless word == "edition_#{number}"

            ordinal = locale_template("edition_ordinal", number)
            return ordinal if ordinal

            cardinal_form || "#{ordinalize(number)} #{@i18n.label('edition')}"
          end

          # The plain cardinal form ("edition 7")
          def cardinal_form
            locale_template("edition_cardinal", number) ||
              locale_template("version_cardinal", number)
          end

          private

          # A locale template carrying {{ var1 }} (optionally through
          # the ordinal_word filter) populated with the edition number;
          # a bare label (no placeholder) is not one
          def locale_template(key, value)
            raw = @i18n.label(key)
            return nil if raw == key || raw !~ /\{{/

            if raw.include?("ordinal_word")
              word = @i18n.label("ordinal_word_#{value}")
              word = ordinalize(value) if word == "ordinal_word_#{value}"
              raw.gsub(/\{\{\s*var1[^}]*\}\}/, word)
            else
              raw.gsub("{{ var1 }}", value.to_s)
            end
          end

          private

          # Worded editions are document editions; online resources
          # carry numbered builds rendered as versions. A standard is a
          # document edition too (its report kind carries the clause 8.11
          # fallback templates, but its numbered editions read as
          # "Nth edition" — the TS contract renders them so).
          def word_edition?
            number.positive? &&
              %w[monograph component_part serial_part report]
                .include?(item_kind)
          end

          def raw
            (@model.edition&.number || @model.edition&.content).to_s
          end

          def number
            Integer(raw)
          rescue ArgumentError, TypeError
            0
          end

          def ordinalize(num)
            "#{num}#{ordinal_suffix(num)}"
          end

          def ordinal_suffix(num)
            case num % 100
            when 11, 12, 13 then "th"
            else
              case num % 10
              when 1 then "st"
              when 2 then "nd"
              when 3 then "rd"
              else "th"
              end
            end
          end
        end
      end
    end
  end
end
