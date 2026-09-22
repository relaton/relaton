module Relaton
  module Ccsds
    # CCSDS document identifier backed by a parsed Pubid::Ccsds::Identifier.
    #
    # Mirrors the IEC flavor (lib/relaton/iec/model/docidentifier.rb): the
    # lutaml `content` stays a plain string for serialization, while the parsed
    # pubid is kept in `@pubid` so the structural mutators (`remove_part!`,
    # `remove_date!`, `to_all_parts!`) can edit the identifier graph and
    # re-render. CCSDS components are simpler than ISO/IEC — plain strings, no
    # subpart, no supplement/consolidated special-casing beyond the base chain —
    # so this is the minimal Pubid-backed shape.
    class Docidentifier < Bib::Docidentifier
      attribute :content, :string

      attr_reader :pubid

      def initialize(arg = nil, **kwargs)
        arg.is_a?(Hash) ? super(arg) : super(**kwargs)
        # lutaml may run the content setter before `type` is assigned; re-run it
        # from `initialize` so the authoritative value is parsed with type set.
        raw = arg.is_a?(Hash) ? (arg["content"] || arg[:content]) : kwargs[:content]
        self.content = raw if raw
      end

      alias_method :original_content=, :content=
      alias_method :original_content, :content

      def content=(value)
        @pubid = nil
        @raw_content = nil

        parsed =
          case value
          when ::Pubid::Ccsds::Identifier then value
          when String
            begin
              ::Pubid::Ccsds::Identifier.parse(value)
            rescue StandardError
              # Suppress while `type` is unset: lutaml runs this setter once
              # during init before `type` is assigned, then `initialize` re-runs
              # it — only the second pass is authoritative.
              Util.warn "Failed to parse Pubid: #{value}" if type
              nil
            end
          end

        if parsed
          @pubid = parsed
        elsif value.is_a?(String)
          @raw_content = value
        end

        send(:original_content=, to_s)
      end

      def content
        return @raw_content if @raw_content
        return @pubid.to_s if @pubid

        original_content
      end

      def to_s
        content.to_s
      end

      def to_all_parts!
        return if !@pubid || @pubid.all_parts?

        # `#exclude` (no args) rebuilds a full independent copy, including
        # the base chain of a supplement/corrigendum — `remove_attr!` walks
        # and mutates that whole chain in place, so even a shallow `.dup`
        # would still lose the original part/date to that mutation.
        original = @pubid.exclude
        remove_part!
        remove_date!
        # `content` is live-derived from `@pubid` (see above), and the wrapped
        # all-parts identifier renders a "(all parts)" marker pubid-ccsds
        # itself never has — so freeze the already-stripped rendering into
        # `@raw_content` (checked first by `content`) before wrapping.
        @raw_content = to_s
        # Wrap the ORIGINAL (unstripped) pubid, not the part/date-stripped
        # working copy above — `identifiers` should hold the real identifier
        # this all-parts reference was derived from.
        @pubid = original.to_all_parts
      end

      def remove_part!
        remove_attr!(:part)
      end

      def remove_date!
        remove_attr!(:date)
      end

      private

      def remove_attr!(attr)
        return unless @pubid

        clear_attr_on(@pubid, attr)
        # Supplements/corrigenda wrap a base identifier; a plain Base returns
        # nil, so the walk clears the attr down the whole chain and terminates.
        node = @pubid.base
        while node
          clear_attr_on(node, attr)
          node = node.base
        end
        refresh_content!
      end

      def clear_attr_on(pubid, attr)
        pubid.send("#{attr}=", nil) if pubid.respond_to?("#{attr}=")
      end

      def refresh_content!
        send(:original_content=, to_s)
      end
    end
  end
end
