module Relaton
  module Isbn
    class Isbn
      #
      # Create ISBN object.
      #
      # @param [String] isbn ISBN 13 number
      #
      def initialize(isbn)
        @isbn = isbn&.delete("-")&.sub(/^ISBN[\s:]/i, "")
      end

      def parse
        convert_to13
      end

      def check?
        case @isbn
        when /^\d{9}[\dX]$/i then check10?
        when /^\d{13}$/ then check13?
        else false
        end
      end

      def check10?
        @isbn[9] == calc_check_digit10
      end

      def check13?
        @isbn[12] == calc_check_digit13
      end

      def calc_check_digit10
        sum = 0
        @isbn[..-2].chars.each_with_index do |c, i|
          sum += c.to_i * (10 - i)
        end
        chk = (11 - sum % 11) % 11
        chk == 10 ? "X" : chk.to_s
      end

      def calc_check_digit13
        sum = 0
        @isbn[..-2].chars.each_with_index do |c, i|
          sum += c.to_i * (i.even? ? 1 : 3)
        end
        ((10 - sum % 10) % 10).to_s
      end

      def convert_to13
        return unless check?

        return @isbn if @isbn.size == 13

        @isbn = "978#{@isbn}"
        @isbn[12] = calc_check_digit13
        @isbn
      end
    end
  end
end
