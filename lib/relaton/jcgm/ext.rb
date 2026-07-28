require_relative "doctype"
require_relative "structured_identifier"

module Relaton
  module Jcgm
    # JCGM bibliographic item extension. JCGM records are BIPM-shaped, so this
    # mirrors `Relaton::Bipm::Ext`: a JCGM `Doctype` and a single
    # `structuredidentifier` (overriding the base collection). `flavor`,
    # `schema_version`, `subdoctype`, `ics` come from the shared `Bib::Ext`.
    class Ext < Bib::Ext
      attribute :doctype, Doctype
      attribute :structuredidentifier, StructuredIdentifier

      xml do
        map_element "structuredidentifier", to: :structuredidentifier
      end

      key_value do
        map_element "structuredidentifier", to: :structuredidentifier
      end
    end
  end
end
