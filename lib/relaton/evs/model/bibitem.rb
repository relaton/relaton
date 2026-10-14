module Relaton
  module Evs
    class Bibitem < Item
      model ItemData
      include Bib::BibitemShared
    end
  end
end
