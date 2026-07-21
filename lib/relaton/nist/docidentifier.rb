module Relaton
  module Nist
    # NIST document identifier backed by a parsed Pubid::Nist::Identifier.
    #
    # Mirrors the CCSDS/IEC flavors (lib/relaton/ccsds/model/docidentifier.rb,
    # lib/relaton/iec/model/docidentifier.rb): the lutaml `content` stays a plain
    # string for serialization, while the parsed pubid is kept in `@pubid` so the
    # base class's abstract structural mutators (`remove_part!`, `remove_date!`,
    # `to_all_parts!`) can edit the identifier graph and re-render.
    #
    # NIST-specific caveats:
    # - **A pubid is only adopted when it round-trips.** A NIST DOI such as
    #   `NIST.SP.800-162` is itself a valid NIST pubid in dotted MR form, but it
    #   must serialize verbatim (its `:human` render is `NIST SP 800-162`). So
    #   `content=` keeps the parsed pubid only when `pubid.to_s(:human)` equals
    #   the input; otherwise the raw string is preserved. This test is
    #   type-independent, so it holds no matter what order lutaml assigns
    #   `content`/`type` on `from_xml`/`from_yaml` (unlike a `type == "NIST"`
    #   gate, which sees a nil `type` on the YAML setter-ordering path).
    # - **The date lives in the `edition` component, not a `:date` attribute.**
    #   NIST has no single date field (`year`/`month` scalars are nil on the
    #   common parse paths); a publication year is carried as the edition id
    #   (`FIPS 46e1977`) or its trailing `additional_text` (`NBS CIRC 11e2.1915`).
    #   So `remove_date!` clears the scalar date fields *and* the edition's
    #   year component, while preserving non-year editions/revisions (`r5`, `e2`).
    #   Dates carried in the `update` component (some NBS supplements) are left
    #   intact — `update` also encodes non-date update codes (`/Upd2`).
    # - **No `(all parts)` rendering.** pubid-nist never emits an all-parts
    #   marker, so `to_all_parts!` degrades to part+date+stage removal and sets
    #   the `all_parts` flag as an (invisible) no-op, matching IEC/CCSDS.
    class Docidentifier < Bib::Docidentifier
      attribute :content, :string

      attr_reader :pubid

      YEAR = /\A\d{4}\z/

      def initialize(arg = nil, **kwargs)
        arg.is_a?(Hash) ? super(arg) : super(**kwargs)
        # `super` normally runs `content=` via lutaml's attribute application; the
        # re-run is a fallback for construction paths that skip it (so the value
        # is parsed exactly once in the common case).
        raw = arg.is_a?(Hash) ? (arg["content"] || arg[:content]) : kwargs[:content]
        self.content = raw if raw && @pubid.nil? && @raw_content.nil?
      end

      alias_method :original_content=, :content=
      alias_method :original_content, :content

      def content=(value)
        @pubid = nil
        @raw_content = nil

        parsed = value.is_a?(::Pubid::Nist::Identifier) ? value : parse_pubid(value)

        # Adopt the pubid only when it renders back to the exact input, so
        # non-canonical forms (DOIs) are preserved as the raw string.
        if parsed && (!value.is_a?(::String) || parsed.to_s(format: :human) == value)
          @pubid = parsed
        elsif value.is_a?(::String)
          @raw_content = value
        end

        send(:original_content=, to_s)
      end

      def content
        return @raw_content if @raw_content
        return @pubid.to_s(format: :human) if @pubid

        original_content
      end

      def to_s
        content.to_s
      end

      def to_all_parts!
        return unless @pubid

        remove_part!
        remove_date!
        remove_stage!
        @pubid.all_parts = true if @pubid.respond_to?(:all_parts=)
        refresh_content!
      end

      def remove_part!
        walk_chain { |node| clear_part_on(node) }
      end

      def remove_stage!
        walk_chain { |node| node.stage = nil if node.respond_to?(:stage=) }
      end

      def remove_date!
        walk_chain { |node| clear_date_on(node) }
      end

      private

      def parse_pubid(value)
        return nil unless value.is_a?(::String) && !value.empty?

        ::Pubid::Nist::Identifier.parse(value)
      rescue StandardError
        Util.warn "Failed to parse Pubid: #{value}"
        nil
      end

      # Apply a mutation to the top pubid and every identifier down the
      # `base` chain (only SupplementIdentifier exposes the chain; a
      # plain identifier returns nil and the walk terminates after one pass).
      def walk_chain
        return unless @pubid

        node = @pubid
        while node
          yield node
          node = node.respond_to?(:base) ? node.base : nil
        end
        refresh_content!
      end

      def clear_part_on(pubid)
        pubid.part = nil if pubid.respond_to?(:part=)
        pubid.parts = nil if pubid.respond_to?(:parts=)
      end

      # NIST spreads the date across scalar fields (mostly nil in practice) and
      # the edition component. Clear the scalars, then strip a year that rides on
      # the edition: a trailing year suffix (`e2.1915` -> `e2`) or a whole
      # bare-year edition (`e1977`/`r2001` -> gone), while leaving numbered
      # editions and revisions (`e2`, `r5`) intact.
      def clear_date_on(pubid)
        %i[year month revision_year revision_month edition_year update_year]
          .each { |f| pubid.send("#{f}=", nil) if pubid.respond_to?("#{f}=") }

        return unless pubid.respond_to?(:edition) && (ed = pubid.edition)

        if ed.respond_to?(:additional_text) && ed.additional_text.to_s.match?(YEAR)
          ed.additional_text = nil
        end
        return unless ed.respond_to?(:id) && ed.id.to_s.match?(YEAR) &&
          (!ed.respond_to?(:additional_text) || ed.additional_text.nil?)

        pubid.edition = nil if pubid.respond_to?(:edition=)
      end

      def refresh_content!
        send(:original_content=, to_s)
      end
    end
  end
end
