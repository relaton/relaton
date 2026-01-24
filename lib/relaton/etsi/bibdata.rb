require_relative "item"

module Relaton
  module Etsi
    class Bibdata < Item
      include Bib::BibdataShared
    end
  end
end
