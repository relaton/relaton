require_relative "doctype"
require_relative "editorial_group"
require_relative "session"

module Relaton
  module Un
    class Ext < Lutaml::Model::Serializable
      attribute :schema_version, :string
      attribute :doctype, Doctype
      attribute :subdoctype, :string
      attribute :submissionlanguage, :string, collection: true
      attribute :editorialgroup, EditorialGroup
      attribute :ics, Bib::ICS, collection: true
      attribute :distribution, :string, values: %w[general limited restricted provisional]
      attribute :session, Session
      attribute :job_number, :string

      xml do
        map_attribute "schema-version", to: :schema_version
        map_element "doctype", to: :doctype
        map_element "subdoctype", to: :subdoctype
        map_element "submissionlanguage", to: :submissionlanguage
        map_element "editorialgroup", to: :editorialgroup
        map_element "ics", to: :ics
        map_element "distribution", to: :distribution
        map_element "session", to: :session
        map_element "job_number", to: :job_number
      end
    end
  end
end
