module Relaton
  module Jis
    class Bibitem < Item
      model ItemData
      include Bib::BibitemShared
    end
  end
end
