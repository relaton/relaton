require_relative "docidentifier"
require_relative "ext"

module Relaton
  module Ogc
    class Item < Iso::Item
      model ItemData

      attribute :docidentifier, Docidentifier, collection: true, initialize_empty: true
      attribute :ext, Ext
    end
  end
end
