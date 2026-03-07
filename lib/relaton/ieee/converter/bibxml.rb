require_relative "bibxml/from_rfcxml"

module Relaton
  module Ieee
    module Converter
      module BibXml
        def self.to_item(xml)
          if xml.include?("<referencegroup") || xml.include?("<Referencegroup")
            Bib::Converter::BibXml.to_item(xml)
          else
            reference = Rfcxml::V3::Reference.from_xml(xml)
            FromRfcxml.new(reference).transform
          end
        end
      end
    end
  end
end
