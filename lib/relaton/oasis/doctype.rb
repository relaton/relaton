module Relaton
  module Oasis
    class Doctype <  Bib::Doctype
      attribute :content, :string, values: %w[specification memorandum resolution standard]
    end
  end
end
