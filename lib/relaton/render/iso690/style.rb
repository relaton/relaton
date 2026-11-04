# frozen_string_literal: true

require "lutaml/model"

module Relaton
  module Render
    module Iso690
      # A citation style as an instance of the relaton-models CitationStyle
      # model: the citation scheme (name form, localized strings), the
      # citation and reference templates, and per-type template variants.
      # All rendering knowledge is data; the engine holds no styles, no
      # vocabularies, no localized strings.
      class Style < Lutaml::Model::Serializable
        autoload :NameForm, "relaton/render/iso690/style/name_form"
        autoload :Locale, "relaton/render/iso690/style/locale"
        autoload :Scheme, "relaton/render/iso690/style/scheme"
        autoload :TemplateMap, "relaton/render/iso690/style/template_map"
        autoload :SortRule, "relaton/render/iso690/style/sort_rule"
        autoload :TypeTemplate, "relaton/render/iso690/style/type_template"

        attribute :name, :string
        # The citation-style family the pack belongs to (iso690 | lncs |
        # chicago | ieee-sa | apa): selects the presentation-of-models
        # conventions the templates address
        attribute :family, :string, default: "iso690"
        # A named pack this one deltas over; resolved at load with the
        # documented merge semantics (#merge_delta)
        attribute :extends, :string
        # Engine capabilities the pack addresses; a resolver that lacks
        # one fails loudly instead of mis-rendering
        attribute :requires, :string, collection: true, default: []
        # Pack-declared taxonomy: wire type -> kind (aliasing or
        # fallthrough), consulted before the engine's Kinds table
        attribute :types, :hash, default: -> { {} }
        # Presentation-of-models selections: slot -> named engine rule
        attribute :rules, :hash, default: -> { {} }
        attribute :scheme, Scheme, default: -> { Scheme.new }
        attribute :templates, TemplateMap, default: -> { TemplateMap.new }
        attribute :per_type, TypeTemplate, collection: true, default: []
        attribute :sort_key, SortRule, collection: true, default: []

        key_value do
          map "name", to: :name
          map "family", to: :family
          map "extends", to: :extends
          map "requires", to: :requires
          map "types", to: :types
          map "rules", to: :rules
          map "scheme", to: :scheme
          map "templates", to: :templates
          map "perType", to: :per_type
          map "sortKey", to: :sort_key
        end

        # The index sort rules; creator then date when the style declares
        # none (the name-and-date default).
        def sort_keys
          return sort_key unless sort_key.empty?

          [SortRule.new(attribute: "creator"), SortRule.new(attribute: "date")]
        end

        # The ISO 690 kind of an item: the vocabulary's mapping, or
        # the style's declared kind for types the vocabulary does not
        # map (a flavor whose untyped items are not reports)
        def kind_for(type)
          declared_type = types[type.to_s]
          unless declared_type.to_s.empty?
            return Kinds.mapped?(declared_type) ? Kinds.kind_for(declared_type) :
              declared_type
          end

          return Kinds.kind_for(type) if Kinds.mapped?(type)

          declared = scheme.default_kind.to_s
          declared.empty? ? Kinds.kind_for(type) : declared
        end

        # Per-type template selection is a data lookup; unmatched types
        # fall back to the general reference template. When a kind has
        # home-flagged variants, the split is resolved by whether the item
        # carries the scheme's home document identifier.
        def template_for(type, home: nil)
          candidates = per_type.select { |t| t.type == type.to_s }
          if candidates.size > 1 && !home.nil?
            candidates = candidates.select { |t| (t.home || false) == home }
          end
          candidates.first&.template || templates.reference
        end

        def type_template_for(type)
          per_type.find { |t| t.type == type.to_s }
        end

        # The home split applies to the short cite as it does to the
        # reference template (a home standard's short cite is not an
        # external standard's)
        def short_template_for(type, home: nil)
          candidates = per_type.select { |t| t.type == type.to_s }
          if candidates.size > 1 && !home.nil?
            candidates = candidates.select { |t| (t.home || false) == home }
          end
          candidates.filter_map(&:short).first
        end

        # The absent-slot replacement text declared for a type, when any
        def fallback_for(type, slot)
          type_template_for(type)&.fallbacks&.[](slot.to_s)
        end

        def title_form_for(type)
          per_type.lazy.select { |t| t.type == type.to_s }
            .find { |t| t.title && !t.title.empty? }&.title
        end

        # First-creator name form: the style's declared name template with
        # the surname upcased, per the name-and-date convention.
        def render_name(surname:, given:)
          shown = scheme.name_form.surname_upcase ? surname.upcase : surname
          Template.new(templates.name).evaluate(
            "surname" => Template::Field[!shown.empty?, shown],
            "givennames" => Template::Field[!given.empty?, given],
          )
        end

        # The documented delta merge: perType entries merge per type
        # key (a delta re-declaring `article` never drops the base's
        # `monograph`); hash sections merge per key; scalars, templates
        # and rule selections replace; sortKey and requires union.
        # Deterministic and engine-portable.
        def merge_delta(base)
          merged_per_type = base.per_type.dup
          per_type.each do |delta|
            index = merged_per_type.find_index do |b|
              b.type == delta.type && (b.home || false) == (delta.home || false)
            end
            index ? merged_per_type[index] = delta : merged_per_type << delta
          end
          self.per_type = merged_per_type
          self.types = base.types.merge(types)
          self.rules = base.rules.merge(rules)
          merge_scheme(base)
          merge_templates(base)
          self.sort_key = (base.sort_key + sort_key).uniq
          self.requires = (base.requires + requires).uniq
          self
        end

        private

        def merge_scheme(base)
          fresh = NameForm.new
          NameForm.attributes.each_key do |attr|
            val = scheme.name_form.send(attr)
            next unless val == fresh.send(attr)

            base_val = base.scheme.name_form.send(attr)
            scheme.name_form.send("#{attr}=", base_val) if
              base_val != fresh.send(attr)
          end

          scheme.system = base.scheme.system if scheme.system.to_s.empty?
          scheme.short_from_reference = base.scheme.short_from_reference unless
            scheme.short_from_reference
          scheme.home_docid_type = base.scheme.home_docid_type if
            Array(scheme.home_docid_type).empty?
          scheme.default_kind = base.scheme.default_kind if
            scheme.default_kind.to_s.empty?

          locale = scheme.locale
          base_locale = base.scheme.locale
          locale.conj ||= base_locale.conj
          locale.others ||= base_locale.others
          locale.no_date ||= base_locale.no_date
          locale.no_author ||= base_locale.no_author
          locale.in_str ||= base_locale.in_str
          locale.at ||= base_locale.at
          locale.available_at ||= base_locale.available_at
          # delta labels win per key; the base's label map only fills
          # gaps. Hash#merge! yields |key, receiver, other|, so the
          # delta value is the second argument.
          locale.labels.merge!(base_locale.label_map) { |_k, delta, _base| delta }
          # a delta's named attributes assert over the inherited labels
          locale.named_label_map.each_key { |k| locale.labels.delete(k) }
          locale.punct = (base_locale.punct || {}).merge(locale.punct || {})
        end

        def merge_templates(base)
          fresh = TemplateMap.new
          TemplateMap.attributes.each_key do |attr|
            val = templates.send(attr)
            base_val = base.templates.send(attr)
            next unless val == fresh.send(attr) && base_val != fresh.send(attr)

            templates.send("#{attr}=", base_val)
          end
        end

        class << self
          def load(name_or_path, seen = [])
            path = style_path(name_or_path) or
              raise ArgumentError, "unknown style #{name_or_path}"
            style = from_yaml(File.read(path))
            return style if style.extends.to_s.empty?

            style.extends.split(/\s+/).each do |base_name|
              raise ArgumentError,
                    "circular extends #{base_name}" if seen.include?(base_name)

              style.merge_delta(load(base_name, seen + [base_name]))
            end
            style
          end

          private

          def style_path(name)
            file = File.join(__dir__, "styles", "#{name}.yml")
            return file if File.file?(file)

            name if name.is_a?(String) && File.file?(name)
          end
        end
      end
    end
  end
end
