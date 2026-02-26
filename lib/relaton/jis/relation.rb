# frozen_string_literal: true

require_relative "item_base"

module Relaton
  module Jis
    class Relation < Bib::Relation
      attribute :bibitem, ItemBase
    end
  end
end
