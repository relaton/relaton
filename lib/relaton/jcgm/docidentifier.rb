module Relaton
  module Jcgm
    # A JCGM document identifier, backed by `Pubid::Jcgm` (mirrors OIML's
    # pubid-backed Docidentifier). Parsing is best-effort: forms pubid doesn't
    # recognise (e.g. the combined bilingual docidentifiers and the French
    # `réunion` form) leave `pubid` nil via the `content=` rescue rather than
    # raising during deserialization.
    class Docidentifier < Bib::Docidentifier
      attr_reader :pubid

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
    end
  end
end
