# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      class Style
        # CitationScheme: the citation system, its name form and its
        # localized strings (relaton-models CitationScheme).
        class Scheme < Lutaml::Model::Serializable
          attribute :system, :string, default: "name-date"
          attribute :name_form, NameForm, default: -> { NameForm.new }
          attribute :locale, Locale, default: -> { Locale.new }
          attribute :home_docid_type, :string, collection: true
          attribute :default_kind, :string, default: ""

          # The renderings' short cite takes the reference form with the
      # first-biblio marker (the 1.x citetemplate short), not the
      # citation template
      attribute :short_from_reference, :boolean, default: -> { false }

      key_value do
            map "system", to: :system
            map "nameForm", to: :name_form
            map "locale", to: :locale
            map "homeDocidType", to: :home_docid_type
            map "defaultKind", to: :default_kind
            map "shortFromReference", to: :short_from_reference
          end
        end
      end
    end
  end
end
