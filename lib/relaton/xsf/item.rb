require_relative "docidentifier"

module Relaton
  module Xsf
    class Item < Bib::Item
      model ItemData

      # Narrow the inherited `docidentifier` to the flavor's own class, so a
      # deserialized item exposes `#pubid` on each id. (The OGC/ECMA shape.)
      attribute :docidentifier, Docidentifier, collection: true, initialize_empty: true
    end
  end
end
