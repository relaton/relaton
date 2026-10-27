module Relaton
  module Ieee
    class ItemData < Bib::ItemData
      # The ISBN and DOI name one edition, so the undated item keeps only the
      # IEEE docids; its `instanceOf` relation still carries them.
      def to_most_recent_reference
        me = super
        me.docidentifier = me.docidentifier.select { |d| d.type == "IEEE" }
        me
      end
    end
  end
end
