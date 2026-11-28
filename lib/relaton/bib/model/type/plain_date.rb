require "date"

module Relaton
  module Bib
    # Value type for validity-class dates that preserves the precision of
    # the input: date-only input serializes as xs:date, input carrying a
    # time serializes as ISO 8601 dateTime ("2010-10-10T12:21:00Z"). The
    # bibdata schema requires dateTime whenever a time is present, so
    # truncating to ::Date silently loses bibitem validity times
    # (relaton#636; the truncating cast shipped in cf535198 for the Bipm
    # static-file round-trip, whose date-only fixtures are unaffected).
    class PlainDate < Lutaml::Model::Type::Date
      def self.cast(value, options = {})
        # String with a time component: parse as ::DateTime, keeping
        # offset and precision (lutaml's Date cast truncates these).
        return ::DateTime.parse(value) if value.is_a?(String) && value =~ /T\d{2}:\d{2}/
        # ::DateTime objects already carry the caller's precision.
        return value if value.is_a?(::DateTime)
        # A string without a time component ("2018-04-15+05:30") is
        # date-only regardless of its zone offset: keep xs:date.
        result = super
        result.is_a?(::DateTime) ? result.to_date : result
      end

      def self.serialize(value, options = {})
        case value
        when ::DateTime
          value.offset.zero? ? value.strftime("%FT%TZ") : value.xmlschema
        when ::Date
          value.iso8601
        else
          super
        end
      end
    end
  end
end
