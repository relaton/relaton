module Relaton
  module Gost
    class Bibdata < Item
      model ItemData
      include Bib::BibdataShared
    end
  end
end
