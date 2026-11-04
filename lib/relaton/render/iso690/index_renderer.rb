# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      # A bibliographic index: the ordered reference list, laid out per the
      # BibliographicStyle instance. Sorting follows the style's declared
      # sortKey rules (creator, then date); numbering is layout data.
      class IndexRenderer
        def initialize(style: "author-date", lang: "en", script: "Latn")
          @style = Style.load(style)
          @i18n = I18n.load(lang).overlay!(@style.scheme.locale)
          @renderer = Renderer.new(style: style, lang: lang, script: script)
        end

        # The reference strings, sorted per the style's sortKey rules.
        def references(models)
          sort_rules = @style.sort_keys
          fields = models.to_h { |m| [m, field_table(m)] }
          models.sort do |a, b|
            fa = fields[a]
            fb = fields[b]
            sort_rules.each do |rule|
              cmp = key_of(fa, rule) <=> key_of(fb, rule)
              next if cmp.zero?

              break(rule.descending? ? -cmp : cmp)
            end || 0
          end.map { |model| @renderer.render(model) }
        end

        # The laid-out index: numbered entries per the layout rules
        # (arabic by default; "none" renders bare references).
        def render(models, numbering: "arabic")
          refs = references(models)
          return refs if numbering == "none"

          refs.each_with_index.map { |ref, i| "#{i + 1}. #{ref}" }
        end

        private

        def field_table(model)
          Fields.new(model, style: @style, i18n: @i18n).to_h
        end

        def key_of(fields, rule)
          field = fields[rule.attribute.to_s.delete("_").downcase]
          return "" if field.nil?

          text = field.respond_to?(:text) ? field.text : field.to_s
          text.downcase
        end
      end
    end
  end
end
