module Relaton
  module Calconnect
    class ItemData < Relaton::Bib::ItemData
      def create_id(without_date: false)
        docid = docidentifier.find(&:primary) || docidentifier.first
        return unless docid

        self.id = docid.content.gsub(/\W+/, "")
      end
    end
  end
end
