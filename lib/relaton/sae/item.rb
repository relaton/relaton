module Relaton
  module Sae
    # An SAE bibliographic item. SAE adds no element to the shared model: the
    # Crossref record maps onto `Bib` as it is, so the only flavor-specific
    # value is `ext/flavor`.
    class Item < Bib::Item
      model ItemData
    end
  end
end
