module Relaton
  module Easc
    # EASC bibliographic item. Re-declares +ext+ to use the typed Ext
    # subclass so EASC-specific fields round-trip natively.
    class Item < Bib::Item
      model ItemData

      attribute :ext, Ext
      attribute :docidentifier, Docidentifier, collection: true,
                                               initialize_empty: true
    end
  end
end
