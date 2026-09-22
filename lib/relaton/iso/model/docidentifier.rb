require_relative "../type/pubid"

module Relaton
  module Iso
    class Docidentifier < Bib::Docidentifier
      attribute :content, Type::Pubid

      attr_reader :pubid

      def initialize(arg = nil, **kwargs)
        arg.is_a?(Hash) ? super(arg) : super(**kwargs)
        # Content may have been set before type during lutaml init. Re-run
        # the setter so type-dependent parsing (e.g. iso-tc bypass) applies.
        raw = arg.is_a?(Hash) ? (arg["content"] || arg[:content]) : kwargs[:content]
        self.content = raw if raw
      end

      alias_method :original_content=, :content=
      alias_method :original_content, :content

      def content=(value)
        @pubid = nil
        @raw_content = nil

        if type == "iso-tc" && value.is_a?(String)
          @raw_content = value
        else
          parsed =
            case value
            when ::Pubid::Iso::Identifier then value
            when String
              begin
                ::Pubid::Iso::Identifier.parse(value)
              rescue StandardError
                # Suppress when type is not yet set (lutaml runs the setter
                # once during init before `type` is assigned, then `initialize`
                # re-runs it; only the second pass is authoritative).
                Util.warn "Failed to parse Pubid: #{value}" if type
                nil
              end
            end

          if parsed
            @pubid = parsed
            # TC committee documents have a canonical spelling ("… N1110")
            # that pubid renders with a space ("… N 1110"). Preserve the
            # source string (same intent as the iso-tc bypass) while keeping
            # the parsed pubid for any structural operations.
            if value.is_a?(String) && parsed.is_a?(::Pubid::Iso::Identifiers::TcDocument)
              @raw_content = value
            end
          elsif value.is_a?(String)
            @raw_content = value
          end
        end

        send(:original_content=, to_s)
      end

      def content
        return @raw_content if @raw_content
        return render_pubid(@pubid) if @pubid

        original_content
      end

      def to_s
        content.to_s
      end

      # `remove_part!`/`remove_date!` are unnecessary here: `to_all_parts`'s
      # own identity computation already excludes part/date (down the whole
      # base chain, so a supplement's own year is dropped too — a disclosed
      # pubid behavior change, not a bug; see spec/iso/…/docidentifier_spec.rb
      # "#to_all_parts!"). `remove_stage!` stays: stage isn't one of the
      # attributes pubid's `all_parts_edition_keys` strips.
      def to_all_parts!
        return unless @pubid

        remove_stage!
        @pubid = @pubid.to_all_parts
        refresh_content!
      end

      def remove_stage!
        remove_attr!(:stage)
      end

      def remove_part!
        remove_attr!(:part)
      end

      def remove_date!
        remove_attr!(:date)
      end

      def exclude_year
        return @raw_content if @raw_content
        return nil unless @pubid

        exclude_date(@pubid)
      end

      private

      def render_pubid(pubid)
        case type
        when "URN" then pubid.to_urn
        when "ISO" then pubid.exclude(:languages).to_s
        when "iso-undated" then exclude_date(pubid).exclude(:languages).to_s
        else
          pubid.to_s
        end
      end

      # Return a copy of +pubid+ with the year removed from it and every
      # identifier in its `base` chain (e.g. the base of an
      # amendment/corrigendum). The original is left untouched.
      def exclude_date(pubid)
        result = pubid.exclude(:date)
        current = result
        while current.base
          current.base = current.base.exclude(:date)
          current = current.base
        end
        result
      end

      def remove_attr!(attr)
        return unless @pubid

        @pubid.send("#{attr}=", nil)
        base = @pubid.base
        while base
          base.send("#{attr}=", nil)
          base = base.base
        end
        refresh_content!
      end

      def refresh_content!
        send(:original_content=, to_s)
      end
    end
  end
end
