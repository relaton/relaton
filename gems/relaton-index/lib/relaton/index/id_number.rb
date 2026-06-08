module Relaton
  module Index
    # Shared narrowing/sort key for structured (pubid) index ids. Type uses it
    # for binary-search narrowing; FileIO uses it to sort the index and detect
    # sortedness. The two MUST agree, so the rule lives in one place.
    module IdNumber
      # One-level narrowing key: a supplement/amendment is filed under its
      # immediate parent's number, everything else under its own number.
      #
      # Pubid 2.x exposes the parent via `.base_identifier` (the LutaML
      # `Pubid::Iso::Identifiers::*` classes that relaton loads at runtime). A
      # standalone `require "pubid-iso"` can instead surface the legacy
      # `Pubid::Iso::Identifier::*` classes, which use `.base`; we accept either
      # so the key is stable in both load orders. The wrong accessor silently
      # falls through to the row's own number and breaks bsearch narrowing.
      def get_id_number(id)
        base = id_base(id)
        ((base && base.number) || id.number).to_s
      end

      def id_base(id)
        if id.respond_to?(:base_identifier) && id.base_identifier
          id.base_identifier
        elsif id.respond_to?(:base) && id.base
          id.base
        end
      end
    end
  end
end
