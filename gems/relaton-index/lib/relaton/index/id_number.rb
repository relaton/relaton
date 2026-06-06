module Relaton
  module Index
    # Shared narrowing/sort key for structured (pubid) index ids. Type uses it
    # for binary-search narrowing; FileIO uses it to sort the index and detect
    # sortedness. The two MUST agree, so the rule lives in one place.
    module IdNumber
      # One-level key: a supplement is filed under its parent's number
      # (base_identifier.number), everything else under its own number.
      # `.base_identifier` is the pubid 2.x API (1.x's `.base` no longer
      # exists); the wrong key here silently disables bsearch narrowing.
      def get_id_number(id)
        if id.respond_to?(:base_identifier) && id.base_identifier
          id.base_identifier.number.to_s
        else
          id.number.to_s
        end
      end
    end
  end
end
