module Relaton
  module Xsf
    class Bibitem < Item
      model ItemData
      include Bib::BibitemShared
    end
  end
end
