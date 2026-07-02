require_relative "ext"
require_relative "item_data"

module Relaton
  module Plateau
    class Item < Bib::Item
      model ItemData

      attribute :ext, Ext
    end
  end
end
