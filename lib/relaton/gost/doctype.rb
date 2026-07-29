module Relaton
  module Gost
    # GOST document types. The value is carried in the inherited
    # `content` attribute. The list mirrors the categories GOST
    # publishes (interstate GOST, Russian national GOST R,
    # preliminary standards, methodological documents).
    class Doctype < Bib::Doctype
      TYPES = %w[
        interstate
        national
        preliminary
        methodological
      ].freeze
    end
  end
end
