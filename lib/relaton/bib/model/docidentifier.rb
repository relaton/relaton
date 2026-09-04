module Relaton
  module Bib
    class Docidentifier < LocalizedMarkedUpString
      attribute :type, :string
      attribute :scope, :string
      attribute :primary, :boolean

      xml do
        root "docidentifier"
        map_attribute "type", to: :type
        map_attribute "scope", to: :scope
        map_attribute "primary", to: :primary
      end

      key_value do
        map "type", to: :type
        map "scope", to: :scope
        map "primary", to: :primary
      end

      # `Bib::ItemData#to_all_parts` and `#to_most_recent_reference` broadcast
      # these three to EVERY docidentifier unconditionally, so raising here made
      # both calls unusable for any flavor that had not subclassed this class —
      # 13 of them had not, and both died on every item they produced. The raise
      # was also `NotImplementedError`, which descends from `ScriptError`, so a
      # caller's `rescue => e` did not even catch it.
      #
      # The default is therefore a **no-op**. An identifier that models neither
      # a part nor a date has nothing to strip, and returning it unchanged is
      # the correct answer for both calls.
      #
      # A flavor whose identifier does carry one overrides these — see
      # `Relaton::Ogc::Docidentifier` or `Relaton::Iala::Docidentifier` for the
      # pubid-backed shape (parse `content` into a pubid, mutate, re-render
      # through a `store_content` alias so the write does not re-parse).
      #
      # The trade-off, recorded so it stays a choice rather than an oversight: a
      # flavor that DOES carry a date but has not overridden `remove_date!` now
      # returns a dated reference silently, where before it crashed loudly.
      # That is a missing override in the flavor, not a defect here.

      def remove_part!; end

      def to_all_parts!; end

      def remove_date!; end
    end
  end
end
