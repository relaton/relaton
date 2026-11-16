# frozen_string_literal: true

require_relative "ris/from_ris"
require_relative "ris/to_ris"

module Relaton
  module Bib
    module Converter
      # RIS serialization — the interchange format for EndNote, Zotero,
      # and Reference Manager. Standards map to TY - STD.
      module Ris
        ENTRY_TYPES = {
          "standard" => "STD", "book" => "BOOK", "article" => "JOUR",
          "inbook" => "CHAP", "inproceedings" => "CONF", "report" => "RPRT",
          "thesis" => "THES", "website" => "ELEC", "webresource" => "ELEC",
        }.freeze

        # ItemData -> RIS string
        def self.from_item(item)
          ToRis.new(item).to_s
        end

        # RIS string -> Hash{String=>ItemData}
        def self.to_item(ris_str)
          FromRis.parse(ris_str)
        end
      end
    end
  end
end
