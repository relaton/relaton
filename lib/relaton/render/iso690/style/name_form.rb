# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      class Style
        # How personal names are formed, as declared by the style's
        # citation scheme (relaton-models NameFormRules).
        class NameForm < Lutaml::Model::Serializable
          attribute :initials, :boolean, default: -> { false }
          attribute :given_name_first, :boolean, default: -> { false }
          # Where an all-editor creator list's role marker sits relative
          # to the name's terminating period: "glue" renders
          # "NAME (eds.)." (the name-date default), "afterPeriod"
          # renders "NAME. (eds.)" (ISO 690 clause-flavour).
          attribute :role_placement, :string, default: "glue"
          # A completename is rendered, not decomposed; styles that
          # upcase inverted names may declare the completename treatment
          attribute :completename_upcase, :boolean, default: -> { false }
          # Every personal name takes the inverted form (surname first),
          # not just the principal creator
          attribute :inverted_all, :boolean, default: -> { false }
          # "serial": the oxford comma appears at every gap of the
          # creator list, including between two names
          attribute :list_style, :string, default: ""
          # Organization names take the inverted form's casing; small-cap
          # styles keep the declared case
          attribute :org_upcase, :boolean, default: -> { true }
          # When no personal creator exists, the creator slot falls back
          # to the publisher's abbreviation ("ISO: ISO 712, ...")
          attribute :creator_fallback, :string
          # A lone editor still carries the role marker ("(ed.)")
          attribute :lone_editor_marked, :boolean, default: -> { false }
          # Initials without their trailing periods ("Nixon RM")
          attribute :initials_period, :boolean, default: -> { true }
          # The inverted form's surname casing: the name-date convention
          # upcases; small-cap styles keep the declared case
          attribute :surname_upcase, :boolean, default: -> { true }
          # Initials are a list; this separates them ("J. K." vs "J.K.")
          attribute :initials_separator, :string, default: " "
          # The first forename cites in full, the rest as initials
          # ("Milena S."; document-history name forms)
          attribute :subsequent_initials, :boolean, default: -> { false }
          # The direct-order surname casing after the first creator:
          # the name-date convention upcases
          attribute :subsequent_surname_upcase, :boolean,
                    default: -> { true }
          # At this many creators the creator list truncates to the
          # first etalDisplay names with "et al." (0 disables)
          attribute :etal_count, :integer, default: 0
          attribute :etal_display, :integer, default: 0
          # The in-text cite truncates separately from the creator
          # list: at this many creators it shows the first
          # inTextEtalDisplay names with "et al." (0 disables; IEEE
          # cites 3+ as "Aluffi et al." while listing 6 in the
          # bibliography)
          attribute :in_text_etal_count, :integer, default: 0
          attribute :in_text_etal_display, :integer, default: 1
          # Editor lists carry the role marker ("(Eds.)")
          attribute :editors_marked, :boolean, default: -> { true }

          key_value do
            map "initials", to: :initials
            map "givenNameFirst", to: :given_name_first
            map "rolePlacement", to: :role_placement
            map "completenameUpcase", to: :completename_upcase
            map "invertedAll", to: :inverted_all
            map "listStyle", to: :list_style
            map "orgUpcase", to: :org_upcase
            map "creatorFallback", to: :creator_fallback
            map "loneEditorMarked", to: :lone_editor_marked
            map "initialsPeriod", to: :initials_period
            map "surnameUpcase", to: :surname_upcase
            map "initialsSeparator", to: :initials_separator
            map "subsequentInitials", to: :subsequent_initials
            map "subsequentSurnameUpcase", to: :subsequent_surname_upcase
            map "etalCount", to: :etal_count
            map "etalDisplay", to: :etal_display
            map "inTextEtalCount", to: :in_text_etal_count
            map "inTextEtalDisplay", to: :in_text_etal_display
            map "editorsMarked", to: :editors_marked
          end
        end
      end
    end
  end
end
