module Relaton
  module Jis
    class Bibdata < Item
      model ItemData
      include Bib::BibdataShared
    end
  end
end
