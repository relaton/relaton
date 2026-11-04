# frozen_string_literal: true

require "lutaml/model"

module Relaton
  module Render
    module Iso690
      # Language-specific labels and typographic punctuation, declared per
      # language in i18n/<lang>.yml. Adding a language adds a YAML
      # declaration — no code. A style instance's localized strings overlay
      # the language pack; language-varying intra-element punctuation
      # (e.g. French " : " production separator) is declared under
      # `punct:`.
      class I18n < Lutaml::Model::Serializable
        attribute :lang, :string, default: "en"
        attribute :labels, :hash, default: {}
        attribute :punct, :hash, default: {}

        key_value do
          map "lang", to: :lang
          map "labels", to: :labels
          map "punct", to: :punct
        end

        def label(key)
          labels.fetch(key.to_s, key.to_s)
        end

        def punct_fetch(key, default)
          punct.fetch(key, default)
        end

        # Style-instance localized strings win over the language pack.
        def overlay!(locale)
          labels.merge!(locale.label_map)
          punct.merge!(locale.punct || {})
          self
        end

        # Runtime label overrides (a caller's i18n hash): the pack's label
        # names win as the key mapping; unknown keys are ignored.
        def overlay_hash!(hash)
          known = %w[
            edition series_no report_no available_from in and oxford_comma
            ed eds date_range others no_date no_author at
            edition_ordinal edition_cardinal version_cardinal
          ]
          hash.each do |key, value|
            labels[key.to_s] = value if known.include?(key.to_s) && !value.nil?
          end
          self
        end

        class << self
          def load(lang = "en")
            code = lang.to_s.empty? ? "en" : lang
            path = File.join(__dir__, "i18n", "#{code}.yml")
            unless File.file?(path)
              # 1.x carried declarations for every locale isodoc uses; the
              # v2 packs are per-style data. Unknown languages fall back to
              # the English pack rather than killing the whole conversion.
              fallback_warn(code)
              path = File.join(__dir__, "i18n", "en.yml")
              raise ArgumentError, "no i18n declarations for language #{code}" unless File.file?(path)
              # The pack supplies the labels; the requested language still
              # governs localization (bilingual titles select by it)
              return from_yaml(File.read(path)).tap { |i| i.lang = code }
            end

            from_yaml(File.read(path))
          end

          def fallback_warn(code)
            (@fallback_warned ||= {})[code] and return
            @fallback_warned[code] = true
            warn "relaton-render: no i18n declarations for language " \
                 "#{code}; falling back to en"
          end
        end
      end
    end
  end
end
