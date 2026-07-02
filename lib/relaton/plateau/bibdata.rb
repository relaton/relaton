module Relaton
  module Plateau
    class Bibdata < Item
      model ItemData
      include Bib::BibdataShared
    end
  end
end
