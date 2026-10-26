module Relaton
  module Bib
    class Formattedref < LocalizedMarkedUpString
      # No `format` attribute: the bibdata grammar dropped it (relaton-bib
      # #94) — an ingested format= is silently dropped, never re-emitted.
      xml do
        root "formattedref"
      end

      # Handle plain string input from YAML/JSON deserialization
      def self.from_yaml(value)
        return new(content: value) if value.is_a?(String)

        super
      end

      def self.from_json(value)
        return new(content: value) if value.is_a?(String)

        super
      end

      # Serialize as plain string when only content is present
      def self.as(format, instance, options = {})
        return instance.content if simple_content?(instance, format)

        super
      end

      def self.simple_content?(instance, format)
        return false if format == :xml

        instance.language.nil? &&
          instance.script.nil? && instance.locale.nil?
      end
    end
  end
end
