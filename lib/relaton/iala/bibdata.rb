module Relaton
  module Iala
    class Bibdata < Item
      model ItemData
      include Bib::BibdataShared
    end
  end
end
