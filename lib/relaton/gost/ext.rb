module Relaton
  module Gost
    # GOST bibliographic item extension. Adds GOST-specific structured
    # metadata on top of the shared Relaton::Bib::Ext so the fields
    # round-trip through both XML and YAML without per-repo merge hacks.
    # Doctype is referenced lazily via autoload from lib/relaton/gost.rb.
    class Ext < Bib::Ext
      attribute :doctype,  Doctype
      attribute :urn,      :string
      attribute :webpage,  :string
      # ICS classification code (МКС / Межгосударственный классификатор
      # стандартов) — e.g. "13.080.20".
      attribute :ics_code, :string
      # Original-language developer of the standard (РАЗРАБОТЧИК).
      attribute :developer, :string
      # Keyword list (Ключевые слова).
      attribute :keywords, :string, collection: true, initialize_empty: true
      # Page count (Страниц).
      attribute :pages,   :string
      # Original-language designation as printed on the cover
      # (e.g. "ГОСТ Р 71039— 2023") — preserves em-dash and spacing
      # quirks that the parsed Pubid normalises away.
      attribute :designation_original, :string

      xml do
        map_element "urn",                  to: :urn
        map_element "webpage",              to: :webpage
        map_element "ics_code",             to: :ics_code
        map_element "developer",            to: :developer
        map_element "keywords",             to: :keywords
        map_element "pages",                to: :pages
        map_element "designation_original", to: :designation_original
      end

      key_value do
        map_element "urn",                  to: :urn
        map_element "webpage",              to: :webpage
        map_element "ics_code",             to: :ics_code
        map_element "developer",            to: :developer
        map_element "keywords",             to: :keywords
        map_element "pages",                to: :pages
        map_element "designation_original", to: :designation_original
      end
    end
  end
end
