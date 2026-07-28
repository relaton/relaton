module Relaton
  module Easc
    class Bibdata < Item
      model ItemData
      include Bib::BibdataShared
    end
  end
end
