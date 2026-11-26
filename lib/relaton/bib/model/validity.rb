require_relative "type/plain_date"

module Relaton
  module Bib
    class Validity < Lutaml::Model::Serializable
      attribute :begins, PlainDate
      attribute :ends, PlainDate
      attribute :revision, PlainDate
      xml do
        root "validity"
        map_element "validityBegins", to: :begins
        map_element "validityEnds", to: :ends
        map_element "revision", to: :revision
      end
    end
  end
end
