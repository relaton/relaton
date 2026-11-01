module Relaton
  module Bib
    class LocalizedString < LocalizedStringAttrs
      attribute :content, :string

      xml do
        map_content to: :content
      end

      key_value do
        map "content", to: :content
        map "language", to: :language
      end
    end

    class TypedLocalizedString < LocalizedString
      attribute :type, :string

      xml do
        map_attribute "type", to: :type
      end

      key_value do
        map "type", to: :type
      end
    end

    class LocalizedMarkedUpString < LocalizedStringAttrs
      module ContentSanitization
        def content=(value)
          super(Sanitizer.sanitize(value, allowed: sanitizer_allowed))
        end
      end

      # The elements that content keeps; Abstract widens it to blocks.
      def sanitizer_allowed
        Relaton::Bib::Sanitizer::ALLOWED
      end

      # Cast at the assignment layer (lutaml-model#972): a bare scalar
      # assigned to a singular custom-typed attribute (e.g. a relation's
      # description) is wrapped here, so the serializer's type validation
      # sees an instance instead of raising IncorrectModelError.
      def self.cast(value)
        return value if value.is_a?(self)

        new(content: value.to_s)
      end

      attribute :content, :string
      prepend ContentSanitization

      xml do
        map_all to: :content
      end

      key_value do
        map "content", to: :content
        map "language", to: :language
      end
    end
  end
end
