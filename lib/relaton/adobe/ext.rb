module Relaton
  module Adobe
    # Adobe bibliographic item extension. Adds Adobe-specific structured
    # metadata on top of the shared Relaton::Bib::Ext so the fields
    # round-trip through both XML and YAML without per-repo merge hacks.
    # Doctype is referenced lazily via autoload from lib/relaton/adobe.rb.
    class Ext < Bib::Ext
      attribute :doctype,           Doctype
      attribute :urn,               :string
      attribute :webpage,           :string
      attribute :tech_note_number,  :string
      attribute :source_repo_path,  :string
      attribute :publication_slug,  :string

      xml do
        map_element "urn",               to: :urn
        map_element "webpage",           to: :webpage
        map_element "tech_note_number",  to: :tech_note_number
        map_element "source_repo_path",  to: :source_repo_path
        map_element "publication_slug",  to: :publication_slug
      end

      key_value do
        map_element "urn",               to: :urn
        map_element "webpage",           to: :webpage
        map_element "tech_note_number",  to: :tech_note_number
        map_element "source_repo_path",  to: :source_repo_path
        map_element "publication_slug",  to: :publication_slug
      end
    end
  end
end
