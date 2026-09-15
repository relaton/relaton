module Relaton
  module Omg
    class Item < Bib::Item
      model ItemData
      attribute :docidentifier, Docidentifier, collection: true, initialize_empty: true
      attribute :ext, Ext
    end
  end
end
