# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      class Style
        # TemplateMap: citation and reference templates as data, plus the
        # title emphasis markers and the first-creator name form. Slots
        # name ISO 690 clause 7 data elements or name-form fields.
        class TemplateMap < Lutaml::Model::Serializable
          attribute :title_open, :string, default: "_"
          attribute :title_close, :string, default: "_"
          attribute :citation, :string, default: "{{surname}}, {{date}}"
          attribute :reference, :string
          attribute :name, :string, default: "{{surname}}, {{givenNames}}"
          attribute :series, :string, default: ""
          attribute :uri, :string, default: ""
          attribute :creators, :string, default: ""
          attribute :uri_short, :string, default: ""
          # "first": cite only the first identifier (1.x
          # authoritative_identifier|first styles)
          attribute :identifier_mode, :string, default: "all"

          key_value do
            map "titleOpen", to: :title_open
            map "titleClose", to: :title_close
            map "citation", to: :citation
            map "reference", to: :reference
            map "name", to: :name
          map "series", to: :series
          map "uri", to: :uri
          map "creators", to: :creators
          map "uriShort", to: :uri_short
          map "identifierMode", to: :identifier_mode
          end
        end
      end
    end
  end
end
