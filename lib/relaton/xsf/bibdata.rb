module Relaton
  module Xsf
    class Bibdata < Item
      model ItemData
      include Bib::BibdataShared
    end
  end
end
