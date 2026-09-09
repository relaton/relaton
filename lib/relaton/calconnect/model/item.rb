require "relaton/bib"
require_relative "../item_data"
require_relative "../docidentifier"
require_relative "ext"

module Relaton
  module Calconnect
    class Item < Bib::Item
      model ItemData

      # The flavor's own Docidentifier, so every parsed record carries a
      # `#pubid` for `DataFetcher#index_id` to key the index-v2 on. Bibitem and
      # Bibdata subclass Item, so they inherit it.
      attribute :docidentifier, Docidentifier, collection: true,
                                               initialize_empty: true

      attribute :ext, Ext
    end
  end
end
