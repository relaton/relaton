module Relaton
  module Gost
    class Bibitem < Item
      model ItemData
      include Bib::BibitemShared
    end
  end
end
