require_relative "../../iso/type/pubid"

module Relaton
  module Bsi
    # BSI document identifier. Keeps the parsed `Pubid::Bsi::Identifier` as the
    # single stored value of `content` (via `Iso::Type::Pubid`, which preserves
    # the instance on the way in and stringifies it on the way out), so there is
    # one source of truth for the identifier — `#pubid` returns it and `#content`
    # renders it to a string. Non-BSI identifiers (e.g. ISBN) and anything pubid
    # can't parse are stored verbatim as plain strings.
    class Docidentifier < Bib::Docidentifier
      attribute :content, Iso::Type::Pubid

      def initialize(arg = nil, **kwargs)
        arg.is_a?(Hash) ? super(arg) : super(**kwargs)
        # Content may have been set before type during lutaml init. Re-run the
        # setter so the type-dependent parse (e.g. the ISBN bypass) applies.
        raw = arg.is_a?(Hash) ? (arg["content"] || arg[:content]) : kwargs[:content]
        self.content = raw if raw
      end

      alias_method :original_content=, :content=
      alias_method :original_content, :content

      # Store the parsed pubid instance (or the raw string for ISBN / anything
      # pubid can't parse) as the single source of truth.
      def content=(value)
        send(:original_content=, parse_pubid(value) || value)
      end

      # The rendered identifier — pubid instances are stringified.
      # @return [String, nil]
      def content
        original_content&.to_s
      end

      # The parsed identifier, when the content is a BSI reference.
      # @return [Pubid::Bsi::Identifier, nil]
      def pubid
        c = original_content
        c if c.is_a?(::Pubid::Bsi::Identifier)
      end

      def to_s
        content.to_s
      end

      # Strip the publication date to build a most-recent (undated) reference.
      # pubid's `exclude` propagates into nested identifiers (so a consolidated
      # base date is dropped while the amendment is kept); `:month` is excluded
      # alongside `:date` because Flex stores the month separately.
      def remove_date!
        return unless pubid

        self.content = pubid.exclude(:date, :month)
      end

      private

      # @return [Pubid::Bsi::Identifier, nil]
      def parse_pubid(value)
        case value
        when ::Pubid::Bsi::Identifier then value
        when String
          return nil if type == "ISBN"

          begin
            ::Pubid::Bsi::Identifier.parse(value)
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
