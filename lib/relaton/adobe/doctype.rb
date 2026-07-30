module Relaton
  module Adobe
    # Adobe publication document types. The value is carried in the
    # inherited `content` attribute (e.g. `tech-note`, `publication`).
    # The list mirrors the categories Adobe publishes through this
    # dataset (font tech notes and named publications).
    class Doctype < Bib::Doctype
      TYPES = %w[
        tech-note
        publication
      ].freeze
    end
  end
end
