module Relaton
  module Easc
    # Structured EASC document identifier. The docid string is the canonical
    # citation form (e.g. "ПМГ 03-2025", "РМГ 151-2025"), parsed into a
    # `Pubid::Easc::Identifier` kept in `@pubid` while the lutaml `content`
    # attribute stays a plain string for serialization.
    #
    # Parsing is **soft**: `content=` lazily requires pubid and rescues
    # `LoadError`/`StandardError`, so a missing gem or non-EASC content leaves
    # `@pubid` nil rather than raising.
    #
    # This was an empty subclass, which meant it inherited
    # `Bib::Docidentifier`'s abstract `remove_part!` / `remove_date!` /
    # `to_all_parts!`. `Bib::ItemData` broadcasts all three to every
    # docidentifier, so `#to_all_parts` and `#to_most_recent_reference` raised
    # `NotImplementedError` on **every** EASC item — and it descends from
    # `ScriptError`, so a caller's `rescue => e` did not catch it.
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
        return unless value

        @pubid = begin
          require "pubid"
          ::Pubid::Easc.parse(value)
        rescue LoadError, StandardError
          nil
        end
      end

      # `Pubid::Easc::Identifier` models publisher/series/variant/number/year,
      # so the mapping is EASC-specific:
      #
      # - **`remove_date!` → clears `year`.** EASC carries no separate date
      #   component; the year is the edition discriminator, so clearing it
      #   yields the undated ("most recent") reference: `ПМГ 03-2025` →
      #   `ПМГ 03`.
      # - **`remove_part!` → clears the (unused) `part`/`subpart`.** EASC models
      #   no part, so this is a no-op for the rendered string; implemented so it
      #   never raises, and it starts working if pubid-easc ever adds one.
      # - **`to_all_parts!` → both, plus `all_parts`** behind a `respond_to?`
      #   guard; the EASC renderer emits no marker for it, so the stripped id is
      #   the best available rendering.
      #
      # All three no-op safely when `@pubid` is nil.

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
