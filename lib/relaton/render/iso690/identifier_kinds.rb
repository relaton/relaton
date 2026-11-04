# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      # Standard and persistent identifiers (ISO 690 clause 7.11): each
      # identifier kind carries its own rendering method. Kinds are keyed by
      # the docidentifier's type attribute — never guessed from content.
      # Flavors register additional kinds (e.g. Pubid::Iala's MRN).
      module IdentifierKinds
        KINDS = {
          "DOI" => ->(content) { "https://doi.org/#{content}" },
          "ISBN" => ->(content) { "ISBN #{content}" },
          "ISSN" => ->(content) { "ISSN #{content}" },
          "URN" => ->(content) { content },
          "MRN" => ->(content) { content },
        }.freeze

        class << self
          def render(docidentifier)
            content = docidentifier.content.to_s
            kind = KINDS[docidentifier.type]
            kind ? kind.call(content) : content
          end
        end
      end
    end
  end
end
