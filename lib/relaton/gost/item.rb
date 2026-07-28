module Relaton
  module Gost
    # GOST bibliographic item. Re-declares +ext+ to use the typed Ext
    # subclass so GOST-specific fields round-trip natively. Sub-files
    # (ItemData, Ext, Docidentifier) are loaded lazily via the autoload
    # entries declared in lib/relaton/gost.rb.
    class Item < Bib::Item
      model ItemData

      attribute :ext, Ext
      attribute :docidentifier, Docidentifier, collection: true,
                                               initialize_empty: true
    end
  end
end
