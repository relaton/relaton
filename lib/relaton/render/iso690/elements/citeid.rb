# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      module Elements
        # The cited identifier with the item's status beside it and the
        # list comma ("OGC 05-020r27 (Draft)," / "ISO 712,"): the comma
        # stays with the identifier whichever side of the status it
        # follows
        class Citeid < Element
          def present?
            identifier_element.present?
          end

          def render
            text = identifier_element.render
            stage = status_element.present? ? status_element.render : ""
            stage.empty? ? "#{text}," : "#{text}#{stage},"
          end

          private

          def identifier_element
            @identifier_element ||=
              Identifier.new(@model, style: @style, i18n: @i18n, kind: @kind,
                                    short: @short)
          end

          def status_element
            @status_element ||=
              Status.new(@model, style: @style, i18n: @i18n, kind: @kind,
                                 short: @short)
          end
        end
      end
    end
  end
end
