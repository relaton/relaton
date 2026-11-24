module Relaton
  module Wmo
    class Bibitem < Item
      model ItemData
      include Bib::BibitemShared
    end
  end
end
