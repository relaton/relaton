# frozen_string_literal: true

module Relaton
  module Jis
    class ItemBase < Item
      model ItemData

      include Bib::ItemBaseAttributes
    end
  end
end
