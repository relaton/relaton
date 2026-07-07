require_relative "item_base"

module Relaton
  module Iala
    class Relation < Bib::Relation
      attribute :bibitem, ItemBase
    end
  end
end
