module Relaton
  module Plateau
    class Bibitem < Item
      model ItemData
      include Bib::BibitemShared
    end
  end
end
