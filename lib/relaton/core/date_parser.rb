module Relaton
  module Core
    module DateParser
      # @param date [String, Integer, Date] date
      # @param str [Boolean] return string or Date
      # @return [Date, String, nil] date
      def parse_date(date, str: true) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/MethodLength
        return date if date.is_a?(Date)

        case date.to_s
        when /(?<date>\w+\s\d{4})/ # February 2012
          format_date $~[:date], "%B %Y", str, "%Y-%m"
        when /(?<date>\w+\s\d{1,2},\s\d{4})/ # February 11, 2012
          format_date $~[:date], "%B %d, %Y", str, "%Y-%m-%d"
        when /(?<date>\d{4}-\d{1,2}-\d{1,2})/ # 2012-02-03 or 2012-2-3
          format_date $~[:date], "%Y-%m-%d", str
        when /(?<date>\d{4}-\d{1,2})/ # 2012-02 or 2012-2
          format_date $~[:date], "%Y-%m", str
        when /(?<date>\d{4})/ # 2012
          format_date $~[:date], "%Y", str
        end
      end

      private

      #
      # Parse date string to Date object and format it
      #
      # @param [String] date date string
      # @param [String] format format string
      # @param [Boolean] str return string if true in other case return Date
      # @param [String, nil] outformat output format
      #
      # @return [Date, String] date object or formatted date string
      #
      def format_date(date, format, str, outformat = nil)
        date = Date.strptime(date, format)
        str ? date.strftime(outformat || format) : date
      end
    end
  end
end
