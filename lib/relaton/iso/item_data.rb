module Relaton
  module Iso
    class ItemData < Bib::ItemData
      def create_id(without_date: false)
        docid = docidentifier.find(&:primary) || docidentifier.first
        return unless docid

        if docid.content.is_a?(String)
          create_id_from_string(docid.content, without_date)
        else
          create_id_from_pubid(docid.content, without_date)
        end
      end

      # These item-level transforms rewrite every docidentifier in place
      # (all-parts / date removal). That can collapse the `iso-undated`
      # entry onto the primary, so re-run the same de-dup the builders apply
      # at construction time (see DataParser#undated_docid).
      def to_all_parts
        drop_redundant_undated_docid(super)
      end

      def to_most_recent_reference
        drop_redundant_undated_docid(super)
      end

      private

      def drop_redundant_undated_docid(item)
        primary = item.docidentifier.find(&:primary)
        return item unless primary

        item.docidentifier = item.docidentifier.reject do |d|
          !d.primary && d.type == "iso-undated" && d.to_s == primary.to_s
        end
        item
      end

      def create_id_from_string(content, without_date)
        pubid = without_date ? content.sub(/:\d{4}$/, "") : content
        self.id = pubid.gsub(/\W+/, "")
      end

      def create_id_from_pubid(content, without_date)
        pubid = without_date ? content.exclude(:year) : content
        self.id = pubid.to_s.gsub(/\W+/, "")
      end
    end
  end
end
