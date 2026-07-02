module Relaton
  module Etsi
    class Doctype < Bib::Doctype
      DOCTYPES = {
        "EN" => "European Standard",
        "ES" => "ETSI Standard",
        "EG" => "ETSI Guide",
        "TS" => "Technical Specification",
        "GS" => "Group Specification",
        "GR" => "Group Report",
        "TR" => "Technical Report",
        "ETR" => "ETSI Technical Report",
        "GTS" => "GSM Technical Specification",
        "SR" => "Special Report",
        "TCRTR" => "Technical Committee Reference Technical Report",
        "TBR" => "Technical Basis for Regulation",
        "ETS" => "European Telecommunication Standard",
        "I-ETS" => "Interim European Telecommunication Standard",
        "NET" => "Norme Européenne de Télécommunication",
      }.freeze

      attribute :abbreviation, :string, values: DOCTYPES.keys
      attribute :content, :string, values: DOCTYPES.values

      def self.create_from_abbreviation(abbreviation)
        new(content: DOCTYPES[abbreviation], abbreviation: abbreviation)
      end
    end
  end
end
