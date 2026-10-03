require "isoics"

module Relaton
  module Bib
    class ICS < Lutaml::Model::Serializable
      attribute :code, :string
      attribute :text, :string

      xml do
        root "ics"
        map_element "code", to: :code
        map_element "text", to: :text
      end

      # Returns the explicit text if set, else the Isoics description for
      # `code`. Kept for consumers that read `.text` directly.
      def text
        return @text if @text.is_a?(String) && !@text.empty?

        Isoics.fetch(code)&.description if code.is_a?(String) && !code.empty?
      end

      # When code is assigned, eagerly populate text from Isoics if no
      # explicit text has been set. Going through the public writer
      # registers the value with the lutaml-model `value_set_for` tracker
      # so the attribute is emitted on serialization.
      def code=(val)
        super
        return unless val.is_a?(String) && !val.empty?
        return if @text.is_a?(String) && !@text.empty?

        populate_text_from_isoics
      end

      # When the deserializer reaches the end of the XML element and
      # records that <text> was absent, it calls `using_default_for(:text)`
      # to mark the attribute as default-valued (suppressing serialization).
      # Refuse that mark if we've already populated text from Isoics so the
      # value survives round-trip. See #112.
      # lutaml-model 0.8.92 (lutaml/lutaml-model#922): assignments made
      # inside `code=` while from_xml is still mid-element do not register
      # as explicit values. Populate once deserialization has finished.
      def self.from_xml(node)
        ics = super
        # lutaml-model 0.8.92 (#922): a value assigned through a custom
        # writer's `super` mid-deserialization is left default-suppressed.
        # Register code as explicitly set, then populate text.
        ics.value_set_for(:code) if ics.code.is_a?(String) && !ics.code.empty?
        ics.populate_text_from_isoics
        ics
      end

      def populate_text_from_isoics
        code.is_a?(String) && !code.empty? or return
        @text.is_a?(String) && !@text.empty? and return

        description = Isoics.fetch(code)&.description
        self.text = description if description
      end

      def using_default_for(attribute_name)
        # lutaml-model 0.8.92 (#922) leaves values assigned through a
        # custom writer's `super` default-suppressed. code, when present,
        # is always explicit; text absent from the XML is filled from
        # Isoics here — the element end — and emitted.
        if attribute_name == :code
          return value_set_for(:code) if @code.is_a?(String) && !@code.empty?

          return super
        end

        return if attribute_name == :text && @text.is_a?(String) && !@text.empty?

        if attribute_name == :text
          populate_text_from_isoics
          return value_set_for(:text) unless @text.nil? || @text.empty?
        end

        super
      end
    end
  end
end
