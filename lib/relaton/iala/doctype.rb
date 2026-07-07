module Relaton
  module Iala
    # IALA publication document types. The value is carried in the
    # inherited `content` attribute (e.g. `standard`, `recommendation`).
    # The list mirrors the seven categories the IALA site exposes.
    class Doctype < Bib::Doctype
      TYPES = %w[
        standard
        recommendation
        guideline
        manual
        model-course
        report
        resolution
      ].freeze
    end
  end
end
