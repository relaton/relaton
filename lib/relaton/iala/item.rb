module Relaton
  module Iala
    # IALA bibliographic item. Re-declares +ext+ to use the typed Ext
    # subclass so IALA-specific fields round-trip natively. Sub-files
    # (ItemData, Ext, Docidentifier, Relation) are loaded lazily via the
    # autoload entries declared in lib/relaton/iala.rb.
    class Item < Bib::Item
      model ItemData

      attribute :ext, Ext
      attribute :docidentifier, Docidentifier, collection: true,
                                               initialize_empty: true
    end
  end
end

# Wire up the back-reference: an Item's relation collection contains
# Relation nodes whose bibitem is an ItemBase. Referencing
# Relaton::Iala::Relation triggers its autoload.
Relaton::Iala::Item.attribute :relation, Relaton::Iala::Relation,
                              collection: true, initialize_empty: true
