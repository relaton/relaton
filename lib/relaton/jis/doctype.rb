module Relaton
  module Jis
    class Doctype < Bib::Doctype
      TYPES = %w[japanese-industrial-standard technical-report technical-specification amendment].freeze

      attribute :type, :string, values: TYPES
    end
  end
end
