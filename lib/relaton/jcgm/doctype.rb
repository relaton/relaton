module Relaton
  module Jcgm
    # JCGM document types. Meetings are `meeting-report`; the guides/GUM/VIM
    # records carry `international-standard` (the shape they were filed with
    # under BIPM). The list is intentionally not enforced as an enum so any
    # unforeseen dataset value still round-trips (mirrors OIML's Doctype).
    class Doctype < Bib::Doctype
      TYPES = %w[meeting-report guide international-standard vocabulary
                 monographie rapport].freeze
    end
  end
end
