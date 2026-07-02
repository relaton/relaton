# frozen_string_literal: true

module Relaton
  module Jis
    class Docidentifier < Bib::Docidentifier
      def remove_part!
        content&.sub!(/-\d+/, "")
      end

      def remove_date!
        content&.sub!(/:\d{4}/, "")
      end

      def to_all_parts!
        remove_part!
        remove_date!
        self.content = "#{content} (all parts)" if content
      end
    end
  end
end
