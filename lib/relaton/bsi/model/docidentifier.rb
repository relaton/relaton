module Relaton
  module Bsi
    class Docidentifier < Bib::Docidentifier
      def remove_date!
        content&.sub!(/:\d{4}(?:-\d{2})?/, "")
      end
    end
  end
end
