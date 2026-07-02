require_relative "item_data"
require_relative "ext"
require_relative "docidentifier"

module Relaton
  module Oiml
    class Item < Bib::Item
      model ItemData

      attribute :ext, Ext
      attribute :docidentifier, Docidentifier, collection: true,
                                               initialize_empty: true
    end
  end
end

require_relative "relation"

Relaton::Oiml::Item.attribute :relation, Relaton::Oiml::Relation,
                              collection: true, initialize_empty: true
