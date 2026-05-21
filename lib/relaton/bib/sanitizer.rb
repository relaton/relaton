require "nokogiri"

module Relaton
  module Bib
    # Strips inline markup not in the basicdoc PureTextElement set
    # (plus <p>, <eref>, <xref>) from raw marked-up content strings.
    # Disallowed elements are unwrapped: tags removed, inner text kept.
    module Sanitizer
      ALLOWED = %w[
        em strong sub sup tt underline strike smallcap br stem
        p eref xref
      ].freeze

      RENAME = {
        "italic" => "em",
      }.freeze

      TAG_RX = %r{<[a-zA-Z/!?]}

      def self.sanitize(content)
        return content unless sanitizable?(content)

        fragment = Nokogiri::XML::DocumentFragment.parse(content)
        return content if fragment.errors.any?

        sanitize_children(fragment)
        fragment.children.map { |c| c.to_xml(encoding: "UTF-8") }.join
      end

      def self.sanitizable?(content)
        content.is_a?(::String) && !content.empty? && content.match?(TAG_RX)
      end
      private_class_method :sanitizable?

      def self.sanitize_children(node)
        node.children.to_a.each do |child|
          next unless child.element?

          child.name = RENAME[child.name] if RENAME.key?(child.name)
          sanitize_children(child)
          child.replace(child.children) unless ALLOWED.include?(child.name)
        end
      end
      private_class_method :sanitize_children
    end
  end
end
