module Relaton
  module Bib
    class Abstract < LocalizedMarkedUpString
      attribute :format, :string

      xml do
        root "abstract"
        map_attribute "format", to: :format
      end

      key_value do
        map "format", to: :format
      end

      # biblio.rng admits basicdoc blocks in <abstract> only.
      def sanitizer_allowed
        Relaton::Bib::Sanitizer::ALLOWED_WITH_BLOCKS
      end
    end
  end
end
