module Relaton
  module Cen
    class Bibdata < Item
      model ItemData
      include Bib::BibdataShared
    end
  end
end
