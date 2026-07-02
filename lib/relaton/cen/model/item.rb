require_relative "../item_data"
require_relative "docidentifier"
require_relative "ext"

module Relaton
  module Cen
    class Item < Bib::Item
      model ItemData

      attribute :docidentifier, Docidentifier, collection: true, initialize_empty: true
      attribute :ext, Ext
    end
  end
end
