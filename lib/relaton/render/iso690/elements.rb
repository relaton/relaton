# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      # Element registry (ISO 690 clause 7 vocabulary)
      module Elements
        autoload :Creator, "relaton/render/iso690/elements/creator"
        autoload :Title, "relaton/render/iso690/elements/title"
        autoload :Edition, "relaton/render/iso690/elements/edition"
        autoload :Medium, "relaton/render/iso690/elements/medium"
        autoload :Series, "relaton/render/iso690/elements/series"
        autoload :Production, "relaton/render/iso690/elements/production"
        autoload :PubDate, "relaton/render/iso690/elements/pub_date"
        autoload :Identifier, "relaton/render/iso690/elements/identifier"
        autoload :Location, "relaton/render/iso690/elements/location"
        autoload :Numeration, "relaton/render/iso690/elements/numeration"
        autoload :ComponentPart, "relaton/render/iso690/elements/component_part"
        autoload :Size, "relaton/render/iso690/elements/size"
        autoload :Extent, "relaton/render/iso690/elements/extent"
        autoload :Access, "relaton/render/iso690/elements/access"
        autoload :Stddoc, "relaton/render/iso690/elements/stddoc"
        autoload :Status, "relaton/render/iso690/elements/status"
        autoload :Authorizer, "relaton/render/iso690/elements/authorizer"
        autoload :Citeid, "relaton/render/iso690/elements/citeid"
        autoload :Updated, "relaton/render/iso690/elements/updated"

        CLASSES = {
          creator: Creator,
          title: Title,
          edition: Edition,
          medium: Medium,
          series: Series,
          production: Production,
          date: PubDate,
          identifier: Identifier,
          location: Location,
          numeration: Numeration,
          component_part: ComponentPart,
          size: Size,
          extent: Extent,
          access: Access,
          stddoc: Stddoc,
          status: Status,
          authorizer: Authorizer,
          citeid: Citeid,
          updated: Updated,
        }.freeze

        class << self
          # Flavors extend the vocabulary through the renderer's
          # element map: a flavor slot resolves before the built-ins,
          # scoped to that renderer alone (never process-wide)
          def resolve(name, elements = {})
            elements[name.to_sym] || CLASSES.fetch(name, nil)
          end
        end

        def self.build(name, model, style:, i18n:, short: false,
                       elements: {})
          klass = resolve(name, elements) or return nil
          klass.new(model, style: style, i18n: i18n, short: short)
        end
      end
    end
  end
end
