module Relaton
  module Wmo
    # Wmo bibliographic item. Re-declares +ext+ to use the typed Ext
    # subclass so Wmo-specific fields round-trip natively. Sub-files
    # (ItemData, Ext, Docidentifier) are loaded lazily via the autoload
    # entries declared in lib/relaton/wmo.rb.
    class Item < Bib::Item
      model ItemData

      attribute :ext, Ext
      attribute :docidentifier, Docidentifier, collection: true,
                                               initialize_empty: true
    end
  end
end
