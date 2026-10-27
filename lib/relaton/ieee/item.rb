require_relative "ext"
require_relative "docidentifier"

module Relaton
  module Ieee
    class Item < Bib::Item
      model ItemData

      attribute :ext, Ext
      attribute :docidentifier, Docidentifier, collection: true,
                                               initialize_empty: true
    end
  end
end
