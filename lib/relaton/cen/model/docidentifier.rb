module Relaton
  module Cen
    class Docidentifier < Bib::Docidentifier
      def remove_date!
        self.content.sub!(/:\d{4}$/, "")
      end
    end
  end
end
