module Relaton
  module Itu
    class Docidentifier < Bib::Docidentifier
      def remove_date!
        self.content = content.gsub(/\s*\((?:\d{2}\/)?\d{4}\)/, "")
      end
    end
  end
end
