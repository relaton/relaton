module Relaton
  module Gost
    # Structured GOST document identifier. Wraps a Pubid::Gost identifier so the
    # canonical citation form (e.g. "GOST R 34.12-2015", "GOST 14946-82") stays
    # in sync with `content`, and undated-reference handling (return the latest
    # edition) can strip the year via the pubid. Mirrors Relaton::Oiml::Docidentifier.
    class Docidentifier < Bib::Docidentifier
      attr_reader :pubid

      # Capture the inherited content setter before overriding #content=, so
      # #refresh_content! can write the re-rendered string back WITHOUT
      # re-parsing. `remove_date!` used to re-sync through `self.content=`,
      # which rebuilds @pubid from the string; harmless on its own, but it
      # would discard the `all_parts = true` that `to_all_parts!` sets.
      alias_method :store_content, :content=

      def initialize(attrs = {}, options = {})
        pubid = attrs.is_a?(Hash) ? attrs.delete(:pubid) : nil
        attrs[:content] ||= pubid.to_s if pubid
        super
        @pubid = pubid if pubid
      end

      def content=(value)
        super
        @pubid = ::Pubid::Gost.parse(value) if value
      rescue StandardError
        @pubid = nil
      end

      # `remove_date!` was implemented but `remove_part!` and `to_all_parts!`
      # were not, so `Bib::ItemData#to_all_parts` still raised
      # `NotImplementedError` on every GOST item — and it descends from
      # `ScriptError`, so a caller's `rescue => e` did not catch it.
      #
      # GOST pubid carries the edition as `year` (not `date`), so `remove_date!`
      # clears that: `GOST R 34.12-2015` -> `GOST R 34.12`. `part`/`subpart`
      # come from the pubid base class and are unused by GOST today, so
      # `remove_part!` is a no-op for the rendered string — implemented so it
      # never raises. All three no-op safely when `@pubid` is nil.

      def remove_part!
        clear_attr!(:part)
      end

      def remove_date!
        clear_attr!(:year)
      end

      def to_all_parts!
        return unless @pubid

        remove_part!
        remove_date!
        @pubid.all_parts = true if @pubid.respond_to?(:all_parts=)
        refresh_content!
      end

      private

      def clear_attr!(attr)
        return unless @pubid && @pubid.respond_to?("#{attr}=")

        @pubid.public_send("#{attr}=", nil)
        @pubid.subpart = nil if attr == :part && @pubid.respond_to?(:subpart=)
        refresh_content!
      end

      def refresh_content!
        store_content(@pubid.to_s) if @pubid
      end
    end
  end
end
