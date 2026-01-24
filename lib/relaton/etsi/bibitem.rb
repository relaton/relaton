require_relative "item"

module Relaton
  module Etsi
    class Bibitem < Item
      include Bib::BibitemShared
    end
  end
end
