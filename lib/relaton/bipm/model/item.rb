require_relative "ext"

module Relaton
  module Bipm
    class Item < Bib::Item
      model ItemData

      attribute :ext, Ext
    end
  end
end
