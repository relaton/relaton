module Relaton
  module Cen
    class StructuredIdentifier < Bib::StructuredIdentifier
      def remove_date!
        self.year = nil
      end
    end
  end
end
