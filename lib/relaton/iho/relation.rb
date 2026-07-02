require_relative "item_base"

module Relaton
  module Iho
    class Relation < Bib::Relation
      attribute :bibitem, ItemBase
    end
  end
end
