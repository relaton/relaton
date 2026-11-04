# frozen_string_literal: true

module Relaton
  module Render
    # Citation rendering per the ISO 690 architecture: a style instance
    # places the inventory's data elements (clause 7) in each resource
    # kind's order (clause 8); the engine is a template evaluator over a
    # field resolver and holds no styles, no vocabularies, no i18n.
    # The v1 compatibility facade (relaton-render#90): isodoc's
    # render-isodoc subclasses Relaton::Render::General.
    autoload :General, "relaton/render/general"

    module Iso690
      autoload :Element, "relaton/render/iso690/element"
      autoload :Elements, "relaton/render/iso690/elements"
      autoload :Fields, "relaton/render/iso690/fields"
      autoload :I18n, "relaton/render/iso690/i18n"
      autoload :IndexRenderer, "relaton/render/iso690/index_renderer"
      autoload :IdentifierKinds, "relaton/render/iso690/identifier_kinds"
      autoload :Kinds, "relaton/render/iso690/kinds"
      autoload :Renderer, "relaton/render/iso690/renderer"
        autoload :Rules, "relaton/render/iso690/rules"
      autoload :Style, "relaton/render/iso690/style"
      autoload :CslImport, "relaton/render/iso690/csl_import"
      autoload :Template, "relaton/render/iso690/template"
    end
  end
end
