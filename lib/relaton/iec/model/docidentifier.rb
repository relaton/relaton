module Relaton
  module Iec
    class Docidentifier < Bib::Docidentifier
      attribute :content, :string

      attr_reader :pubid

      def initialize(arg = nil, **kwargs)
        arg.is_a?(Hash) ? super(arg) : super(**kwargs)
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
          when ::Pubid::Iec::Identifier then value
          when String
            begin
              ::Pubid::Iec::Identifier.parse(value)
            rescue StandardError
              Util.warn "Failed to parse Pubid: #{value}"
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
        return render_pubid(@pubid) if @pubid

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

      def remove_stage!
        remove_attr!(:stage)
      end

      def remove_part!
        remove_attr!(:part)
      end

      def remove_date!
        remove_attr!(:date)
      end

      private

      def render_pubid(pubid)
        case type
        # pubid owns the legacy positional IEC URN format (and the all-parts
        # ":::ser" series form); render through it.
        when "URN" then pubid.to_urn.to_s
        else pubid.to_s
        end
      end

      def remove_attr!(attr)
        return unless @pubid

        # For supplements (Amendment/Corrigendum, which carry their own
        # date/version as an addition to the base), preserve the
        # supplement's own attrs and only clear the base chain — e.g.
        # "IEC 60027-1:1992/AMD1:1997" should drop the base year but keep
        # the amendment year. For wrappers (VapIdentifier, ConsolidatedIdentifier),
        # clear the outer attr too — they re-state the base year and need it
        # gone everywhere.
        unless @pubid.is_a?(::Pubid::Iec::SupplementIdentifier)
          clear_attr_on(@pubid, attr)
        end

        node = @pubid.base_identifier
        while node
          clear_attr_on(node, attr)
          # ConsolidatedIdentifier carries a sibling collection of bundled
          # identifiers; clear the attr on each non-supplement entry too.
          if node.respond_to?(:identifiers) && node.identifiers
            node.identifiers.each do |id|
              next if id.is_a?(::Pubid::Iec::SupplementIdentifier)

              clear_attr_on(id, attr)
            end
          end
          node = node.base_identifier
        end
        refresh_content!
      end

      # Clear one attribute on a single pubid; for :part also clear the
      # paired :subpart (pubid 2.x splits "16-1-1" into part="1" + subpart="1").
      def clear_attr_on(pubid, attr)
        pubid.send("#{attr}=", nil) if pubid.respond_to?("#{attr}=")
        return unless attr == :part && pubid.respond_to?(:subpart=)

        pubid.subpart = nil
      end

      def refresh_content!
        send(:original_content=, to_s)
      end
    end
  end
end
