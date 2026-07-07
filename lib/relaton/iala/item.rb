require_relative "item_data"
require_relative "ext"
require_relative "docidentifier"

module Relaton
  module Iala
    class Item < Bib::Item
      model ItemData

      attribute :ext, Ext
      attribute :docidentifier, Docidentifier, collection: true,
                                               initialize_empty: true
    end
  end
end

require_relative "relation"

Relaton::Iala::Item.attribute :relation, Relaton::Iala::Relation,
                              collection: true, initialize_empty: true
