module Relaton
  module Iho
    class ItemBase < Item
      model ItemData
      include Bib::ItemBaseAttributes
    end
  end
end
