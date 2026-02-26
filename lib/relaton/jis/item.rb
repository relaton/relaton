require_relative "docidentifier"
require_relative "ext"
require_relative "item_data"

module Relaton
  module Jis
    class Item < Iso::Item
      model ItemData

      attribute :docidentifier, Docidentifier,
                collection: true, initialize_empty: true
      attribute :ext, Ext
    end
  end
end

require_relative "relation"

module Relaton
  module Jis
    class Item
      attribute :relation, Relation,
                collection: true, initialize_empty: true
    end
  end
end
