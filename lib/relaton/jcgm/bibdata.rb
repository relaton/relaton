module Relaton
  module Jcgm
    class Bibdata < Item
      model ItemData
      include Bib::BibdataShared
    end
  end
end
