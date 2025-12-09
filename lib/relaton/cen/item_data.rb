module Relaton
  module Cen
    # Item data class.
    class ItemData < Iso::ItemData
      def create_id(without_date: false)
        docid = docidentifier.find(&:primary) || docidentifier.first
        return unless docid

        pubid = without_date ? docid.content.exclude(:year) : docid.content
        self.id = pubid.to_s(with_prf: true).gsub(/\W+/, "")
      end
    end
  end
end
