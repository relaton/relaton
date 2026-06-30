require "relaton/bib"
require_relative "item_data"
require_relative "ext"
require_relative "status"

module Relaton
  module Etsi
    class Item < Bib::Item
      model ItemData

      attribute :ext, Ext
      attribute :status, Status
    end
  end
end
