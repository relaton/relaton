require_relative "item_data"
require_relative "ext"
require_relative "docidentifier"

module Relaton
  module ThreeGpp
    class Item < Bib::Item
      model ItemData

      attribute :ext, Ext
      # Shadow the Bib::Docidentifier declaration in Bib::ItemShared so items
      # carry the pubid-backed 3GPP identifier. Bibitem and Bibdata subclass
      # Item, so this one declaration covers all three.
      attribute :docidentifier, Docidentifier, collection: true,
                                               initialize_empty: true
    end
  end
end
