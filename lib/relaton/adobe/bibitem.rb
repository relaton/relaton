module Relaton
  module Adobe
    class Bibitem < Item
      model ItemData
      include Bib::BibitemShared
    end
  end
end
