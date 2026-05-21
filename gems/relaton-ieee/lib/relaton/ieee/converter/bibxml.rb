require_relative "bibxml/from_rfcxml"
require_relative "bibxml/from_rfcxml_referencegroup"

module Relaton
  module Ieee
    module Converter
      module BibXml
        def self.to_item(xml)
          if xml.include?("<referencegroup") || xml.include?("<Referencegroup")
            referencegroup = Rfcxml::V3::Referencegroup.from_xml(xml)
            FromRfcxmlReferencegroup.new(referencegroup).transform
          else
            reference = Rfcxml::V3::Reference.from_xml(xml)
            FromRfcxml.new(reference).transform
          end
        end
      end
    end
  end
end
