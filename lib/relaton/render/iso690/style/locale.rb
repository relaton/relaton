# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      class Style
        # LocalizedStrings: per-style overrides of the language pack's
        # connective strings, keyed as in the CitationStyle model.
        class Locale < Lutaml::Model::Serializable
          attribute :conj, :string
          attribute :others, :string
          attribute :no_date, :string
          attribute :no_author, :string
          attribute :in_str, :string
          attribute :at, :string
          attribute :available_at, :string
          # Arbitrary label overrides (edition words, join punctuation,
          # size units): merged over the language pack verbatim.
          attribute :labels, :hash, default: -> { {} }
          # Typographic punctuation overrides (production order and
          # separator), declared as in the language packs
          attribute :punct, :hash, default: -> { {} }

          key_value do
            map "and", to: :conj
            map "others", to: :others
            map "noDate", to: :no_date
            map "noAuthor", to: :no_author
            map "in", to: :in_str
            map "at", to: :at
            map "availableAt", to: :available_at
            map "labels", to: :labels
            map "punct", to: :punct
          end

          LABEL_FOR = {
            "conj" => "and", "others" => "others", "no_date" => "no_date",
            "no_author" => "no_author", "in_str" => "in", "at" => "at",
            "available_at" => "available_from",
          }.freeze

          # The named attributes' label map alone: a delta's named
          # attribute (availableAt) outranks the base pack's labels
          # hash carrying the same label key
          def named_label_map
            LABEL_FOR.filter_map do |attr, label|
              value = public_send(attr)
              [label, value] unless value.nil?
            end.to_h
          end

          def label_map
            named_label_map.merge(labels || {})
          end
        end
      end
    end
  end
end
