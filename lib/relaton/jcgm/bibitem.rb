module Relaton
  module Jcgm
    class Bibitem < Item
      model ItemData
      include Bib::BibitemShared
    end
  end
end
