require_relative "docidentifier"
require_relative "ext"

module Relaton
  module Jis
    class Item < Iso::Item
      model Bib::ItemData

      attribute :docidentifier, Docidentifier, collection: true, initialize_empty: true
      attribute :ext, Ext
    end
  end
end
