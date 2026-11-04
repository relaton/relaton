# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      # Field resolver: builds the template evaluator's field table from a
      # relaton model instance. Slots resolve to ISO 690 clause 7 data
      # elements, to name-form fields of the principal creator, or to the
      # disambiguator supplied by the citation caller.
      class Fields
        ELEMENT_SLOTS = %i[
          creator title edition medium series production
          date numeration component_part identifier location size
          extent access stddoc status citeid authorizer updated
        ].freeze

        def initialize(model, style:, i18n:, disambiguator: nil,
                       short: false, elements: {})
          @model = model
          @style = style
          @i18n = i18n
          @disambiguator = disambiguator.to_s
          @short = short
          @elements = elements
        end

        def to_h
          table = {}
          slots.each do |slot|
            key = slot.to_s.delete("_").downcase
            table[key] = element_field(slot)
          end
          table["role"] = role_field
          table["dategroup"] = dategroup_field
          table["disambiguateddate"] = disambiguated_date_field(table["date"])
          unless table["dategroup"].present?
            table["dategroup"] = fallback_field(:dategroup)
          end
          table.merge(name_fields)
        end

        # The creators' editor-role marker ("(eds.)", "（編）"), as a
        # template slot: a creator list that is not all editors cites no
        # role
        def role_field
          creator = Elements.build(:creator, @model, style: @style,
                                   i18n: @i18n, elements: @elements)
          return Template::Field[false, ""] unless
            creator&.present? && creator.respond_to?(:role_marker)

          marker = creator.role_marker
          marker.empty? ? Template::Field[false, ""] :
            Template::Field[true, marker]
        end

        # The date carrying the batch disambiguation suffix ("2022a"):
        # identity when the caller passes none
        def disambiguated_date_field(date)
          return date if @disambiguator.empty? || !date.present?

          Template::Field[true, "#{date.text}#{@disambiguator}"]
        end

        def fallback_field(slot)
          fallback = @style.fallback_for(item_kind, slot)
          fallback ? Template::Field[true, fallback] :
            Template::Field[false, ""]
        end

        private

        # The date with the updated date nested ("(2018 (updated
        # November 2018))"); the bare date slot stays untouched
        def dategroup_field
          date = raw_field(:date)
          updated = raw_field(:updated)
          return Template::Field[false, ""] if !date.present? &&
            !updated.present?

          inner = updated.present? ? updated.text : date.text
          inner = "#{date.text}#{updated.text}" if date.present? &&
            updated.present?
          Template::Field[true, "(#{inner})"]
        end

        private

        def slots
          ELEMENT_SLOTS | @elements.keys
        end

        # The element's own render, before any absent-slot fallback:
        # the creator-date group cites real dates only
        def raw_field(slot)
          element_field = build_field(slot)
          return element_field if element_field.present?

          Template::Field[false, ""]
        end

        def element_field(slot)
          field = build_field(slot)
          return field if field.present?

          fallback = @style.fallback_for(item_kind, slot)
          return Template::Field[true, fallback] if fallback

          Template::Field[false, ""]
        end

        def build_field(slot)
          element = Elements.build(slot, @model, style: @style,
                                   i18n: @i18n, short: @short,
                                   elements: @elements) or
            return Template::Field[false, ""]
          text = element.render.to_s
          if element.present? && !text.empty?
            return Template::Field[true, text]
          end

          Template::Field[false, ""]
        end

        def item_kind
          @style.kind_for(@model.type)
        end

        def name_fields
          creator = Elements.build(:creator, @model, style: @style,
                                   i18n: @i18n, elements: @elements)
          {
            "surname" => Template::Field[creator.present?, creator.in_text],
            "givennames" => Template::Field[!creator.principal_given.empty?,
                                            creator.principal_given],
            "disambiguator" => Template::Field[!@disambiguator.empty?,
                                               @disambiguator],
          }
        end
      end
    end
  end
end
