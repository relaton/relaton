module Relaton
  module Iala
    class Bibitem < Item
      model ItemData
      include Bib::BibitemShared
    end
  end
end
