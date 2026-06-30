module Relaton
  module Iana
    class Bibdata < Item
      model ItemData
      include Bib::BibdataShared
    end
  end
end
