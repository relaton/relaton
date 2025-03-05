module Relaton
  module Plateau
    class Doctype < Bib::Doctype
      attribute :content, :string, values: %w[handbook technical-report annex]
    end
  end
end
