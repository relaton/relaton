module Relaton
  module ThreeGpp
    # A bibliographic date that also accepts the start of the document's 3GPP
    # Release (`project-start`) and its end, which is the release date of the
    # Release (`released`, relaton-3gpp#13). The RelaxNG grammar takes any text
    # as a date type; only the Bib::Date value list needs the two extra types.
    class Date < Bib::Date
      RELEASE_TYPES = %w[project-start released].freeze

      attribute :type, :string, values: Bib::Date.attributes[:type].options[:values] + RELEASE_TYPES
    end
  end
end
