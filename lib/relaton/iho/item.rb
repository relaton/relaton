require_relative "item_data"
require_relative "ext"

module Relaton
  module Iho
    class Item < Bib::Item
      model ItemData

      attribute :ext, Ext
    end
  end
end

require_relative "relation"

Relaton::Iho::Item.attribute :relation, Relaton::Iho::Relation,
                             collection: true, initialize_empty: true
