module Relaton
  module Jcgm
    # A JCGM document identifier, backed by `Pubid::Jcgm` (mirrors OIML's
    # pubid-backed Docidentifier). Parsing is best-effort: forms pubid doesn't
    # recognise (e.g. the combined bilingual docidentifiers and the French
    # `réunion` form) leave `pubid` nil via the `content=` rescue rather than
    # raising during deserialization.
    class Docidentifier < Bib::Docidentifier
      attr_reader :pubid

      # Capture the inherited content setter before overriding #content=, so
      # #refresh_content! can write the re-rendered string back WITHOUT
      # re-parsing (a re-parse would rebuild @pubid and discard in-place
      # mutations such as `all_parts = true`).
      alias_method :store_content, :content=

      def initialize(attrs = {}, options = {})
        pubid = attrs.is_a?(Hash) ? attrs.delete(:pubid) : nil
        attrs[:content] ||= pubid.to_s if pubid
        super
        @pubid = pubid if pubid
      end

      def content=(value)
        super
        @pubid = ::Pubid::Jcgm.parse(value) if value
      rescue StandardError
        @pubid = nil
      end

      # The class carried `#pubid` but none of `Bib::Docidentifier`'s abstract
      # `remove_part!` / `remove_date!` / `to_all_parts!`, so it looked migrated
      # while still raising `NotImplementedError` on every JCGM item through
      # `Bib::ItemData#to_all_parts` / `#to_most_recent_reference` — and
      # `NotImplementedError` descends from `ScriptError`, so a caller's
      # `rescue => e` did not catch it.
      #
      # `Pubid::Jcgm` keeps the publication date in `date` (a
      # `Components::Date`, unlike EASC's and GOST's plain `year`), so
      # `remove_date!` clears that: `JCGM 100:2008` -> `JCGM 100`. `part` and
      # `subpart` come from the pubid base class and are unused by JCGM today,
      # so `remove_part!` is a no-op for the rendered string — implemented so it
      # never raises.
      #
      # The mutation is applied to the identifier **and to its `#root`**. A
      # supplement/corrigendum wraps the document it amends in `base`, and it
      # exposes its own `date=` while carrying nil there — the year lives on the
      # base. Clearing only the wrapper is therefore a silent no-op:
      # `JCGM 200:2008 Corrigendum` keeps its 2008. Clearing the root as well
      # gives `JCGM 200 Corrigendum`. `#root` is the same accessor
      # `Relaton::Index::Type#candidates_by_number` narrows on, so the two stay
      # consistent.
      #
      # Every write is guarded by `respond_to?`, and all three no-op when
      # `@pubid` is nil — the common case the `content=` rescue exists for (the
      # combined bilingual docidentifiers and the French `réunion` form).

      def remove_part!
        clear_attr!(:part)
      end

      def remove_date!
        clear_attr!(:date)
      end

      def to_all_parts!
        return unless @pubid

        remove_part!
        remove_date!
        return unless @pubid.respond_to?(:all_parts=)

        restore = [[@pubid, :all_parts, @pubid.all_parts]]
        @pubid.all_parts = true
        commit_or_revert restore
      end

      private

      # Clear `attr` on the identifier and on its root, then re-render.
      #
      # Nothing is written unless the mutated identifier still renders. Some
      # JCGM types have no form without the component: a meeting is
      # `JCGM 11st Meeting (2006)`, and the renderer reads `date.year`
      # unconditionally, so dropping the date raises rather than producing a
      # shorter id. Those are put back and the content is left alone — an
      # undated meeting reference does not exist, so leaving the id as-is is the
      # correct answer, and it is certainly better than raising out of
      # `Bib::ItemData#to_most_recent_reference`.
      def clear_attr!(attr)
        return unless @pubid

        targets = [@pubid]
        targets << @pubid.root if @pubid.respond_to?(:root) && !@pubid.root.equal?(@pubid)
        restore = []
        targets.each do |id|
          next unless id.respond_to?("#{attr}=")

          restore << [id, attr, id.public_send(attr)]
          id.public_send("#{attr}=", nil)
          next unless attr == :part && id.respond_to?(:subpart=)

          restore << [id, :subpart, id.subpart]
          id.subpart = nil
        end
        commit_or_revert restore
      end

      # Write the re-rendered id back, or undo the mutation if it cannot be
      # rendered. `restore` is the [receiver, attribute, previous value] list to
      # roll back with.
      def commit_or_revert(restore)
        return if restore.empty?

        rendered = begin
          @pubid.to_s
        rescue StandardError
          restore.each { |id, attr, value| id.public_send("#{attr}=", value) }
          return
        end
        store_content rendered
      end
    end
  end
end
