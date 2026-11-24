module Relaton
  module Wmo
    # WMO publication document types. The value is carried in the
    # inherited `content` attribute. The list mirrors the series the
    # dataset tracks (the Pubid::Wmo series heads) plus the S-100
    # product specifications WMO publishes.
    class Doctype < Bib::Doctype
      TYPES = %w[
        technical-regulations
        technical-document
        technical-report
        report
        specification
      ].freeze
    end
  end
end
