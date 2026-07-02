module Relaton
  module Oasis
    class Bibdata < Item
      model ItemData
      include Bib::BibdataShared
    end
  end
end
