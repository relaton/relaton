module Relaton
  module ThreeGpp
    class ItemData < Bib::ItemData
      def create_id(without_date: false)
        return id if id && !id.empty?

        docid = find_primary_docid
        return unless docid

        pubid = without_date ? docid.content.sub(/:\d{4}$/, "") : docid.content
        self.id = pubid.to_s.sub(/\A3GPP\s+/, "").gsub(/\W+/, "")
      end
    end
  end
end
