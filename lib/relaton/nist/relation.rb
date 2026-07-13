require_relative "item_base"

module Relaton
  module Nist
    class Relation
      attribute :type, :string, values: %w[obsoletedBy supersedes supersededBy]
      attribute :bibitem, ItemBase
    end
  end
end
