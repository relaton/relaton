require "nokogiri"

module Relaton
  module Bib
    # Strips inline markup not in the basicdoc PureTextElement set
    # (plus <p>, <eref>, <xref>, <fn>, <link>) from raw marked-up content
    # strings. Disallowed elements are unwrapped: tags removed, inner text kept.
    #
    # <link> (basicdoc's inline hyperlink) is admitted because it is a valid
    # TextElement child of a biblionote and carries a target URL that must
    # survive the from_xml/to_xml round-trip — dropping it silently loses
    # every URL in amended note.display references (relaton-bib#122).
    #
    # <fn> is admitted beyond strict PureTextElement because bibliographic
    # titles in real Metanorma input routinely carry footnotes (e.g. ISO
    # standards titles with a disclaimer footnote), and downstream
    # consumers — notably relaton-render's own inline-tag allow-list —
    # already accept <fn> as a legitimate child of <title>. Stripping it
    # here would break the round-trip.
    #
    # OPAQUE elements (currently <stem>) are also allowed, but the
    # sanitiser does not descend into them: their contents are out-of-band
    # inline notation (MathML, AsciiMath, LaTeX) rather than basicdoc
    # markup, and must be preserved verbatim. Without the opaque-skip,
    # the recursive walk would unwrap MathML / AsciiMath elements down to
    # bare text nodes — see #116 for the round-trip-loss symptom.
    module Sanitizer
      ALLOWED = %w[
        em strong sub sup tt underline strike smallcap br stem
        p eref xref fn link
      ].freeze

      # Elements whose children are non-basicdoc inline notation
      # (MathML, AsciiMath, LaTeX, …) and must be preserved verbatim
      # rather than sanitised against ALLOWED.
      OPAQUE = %w[stem].freeze

      RENAME = {
        "italic" => "em",
      }.freeze

      TAG_RX = %r{<[a-zA-Z/!?]}

      # Captures a namespace prefix, on a tag or on an attribute: the
      # "jats" of <jats:p> and </jats:italic>, and the "xlink" of
      # xlink:href.
      NS_PREFIX_RX = %r{(?:</?|\s)([A-Za-z_][\w.-]*):(?=[A-Za-z_])}

      # Namespace that declares a prefix which the content leaves
      # undeclared. The sanitiser removes it again before it serialises.
      NS_PLACEHOLDER = "urn:x-relaton-undeclared:%s".freeze

      # Element that carries the placeholder declarations. Its children
      # are the sanitised content, so the element itself never reaches
      # the output.
      NS_WRAPPER = "relaton-sanitizer-root".freeze

      # Extension that lengthens the wrapper name past a collision, and
      # the pattern that measures how far the content already extends it.
      NS_WRAPPER_SUFFIX = "-x".freeze
      NS_WRAPPER_RX = /#{NS_WRAPPER}(?:#{NS_WRAPPER_SUFFIX})*/

      # Reserved prefixes. XML declares both, so the content must not.
      NS_RESERVED = %w[xml xmlns].freeze

      # Serialise without the FORMAT option, so the sanitiser keeps the
      # shape of element-only content instead of adding newlines and
      # indent.
      SAVE_OPTS = Nokogiri::XML::Node::SaveOptions::AS_XML

      def self.sanitize(content)
        return content unless sanitizable?(content)

        node = parse(content)
        return content if node.nil?

        sanitize_children(node)
        node.children.map do |c|
          c.to_xml(encoding: "UTF-8", save_with: SAVE_OPTS)
        end.join
      end

      #
      # Parse the content into a node whose children are the content.
      #
      # @param [String] content The raw marked-up content.
      #
      # @return [Nokogiri::XML::Node, nil] The node, or nil when the
      #   content does not parse.
      #
      def self.parse(content)
        fragment = Nokogiri::XML::DocumentFragment.parse(content)
        return fragment if fragment.errors.empty?

        parse_with_prefixes(content)
      end
      private_class_method :parse

      #
      # Parse content that uses undeclared namespace prefixes.
      #
      # An undeclared prefix is always a parse error, so without this the
      # sanitiser gives up on exactly the third-party markup that needs
      # sanitising most. Declare every prefix that the content uses on a
      # wrapper element, parse, then remove the placeholder namespaces
      # from the elements and from the attributes. See metanorma-pdfa#99.
      #
      # An undeclared prefix inside an OPAQUE <stem> goes as well. The
      # sanitiser cannot keep it: an undeclared prefix in the output is
      # the exact failure that this method removes. Only a namespace that
      # the content declares itself survives verbatim.
      #
      # @param [String] content The raw marked-up content.
      #
      # @return [Nokogiri::XML::Element, nil] The wrapper element, or nil
      #   when the content uses no prefix or does not parse.
      #
      def self.parse_with_prefixes(content)
        decl = placeholder_declarations(content) or return
        name = wrapper_name(content)
        doc = Nokogiri::XML "<#{name} #{decl}>#{content}</#{name}>"
        return unless doc.errors.empty?

        drop_placeholder_namespaces doc.root
      end
      private_class_method :parse_with_prefixes

      #
      # Declare every namespace prefix that the content uses.
      #
      # @param [String] content The raw marked-up content.
      #
      # @return [String, nil] The declarations, or nil when the content
      #   uses no prefix.
      #
      def self.placeholder_declarations(content)
        prefixes = content.scan(NS_PREFIX_RX).flatten.uniq - NS_RESERVED
        return if prefixes.empty?

        prefixes.map do |pfx|
          %(xmlns:#{pfx}="#{format NS_PLACEHOLDER, pfx}")
        end.join(" ")
      end
      private_class_method :placeholder_declarations

      #
      # Name a wrapper element that the content does not close itself.
      #
      # Content that holds the literal end tag of the wrapper would close
      # it early. The document then has more than one root, the parse
      # fails, and the sanitiser gives up on content that it can handle.
      #
      # Extend past the longest run of the suffix that the content already
      # holds, in ONE scan. Growing the name and re-testing with include?
      # is quadratic: each extension re-scans the whole string, and
      # content shaped like "…-root-x-x-x" forces one pass per two
      # characters (measured at 229 ms for 20k characters). The sanitiser
      # runs on every marked-up assignment, on third-party content.
      #
      # @param [String] content The raw marked-up content.
      #
      # @return [String] A name that the content does not contain.
      #
      def self.wrapper_name(content)
        longest = content.scan(NS_WRAPPER_RX).map(&:size).max
        return NS_WRAPPER unless longest

        extra = ((longest - NS_WRAPPER.size) / NS_WRAPPER_SUFFIX.size) + 1
        NS_WRAPPER + (NS_WRAPPER_SUFFIX * extra)
      end
      private_class_method :wrapper_name

      #
      # Remove the placeholder namespaces, and only those.
      #
      # Nokogiri's remove_namespaces! would also strip a namespace that
      # the content declares itself, such as the MathML xmlns inside an
      # OPAQUE <stem>, which must survive verbatim. Match the wrapper's
      # own declarations, so a namespace of the content never matches,
      # whatever its URI.
      #
      # The declarations stay on the wrapper element. Only its children
      # reach the output, so the declarations never leak. Do not
      # serialise the root itself.
      #
      # @param [Nokogiri::XML::Element] root The wrapper element.
      #
      # @return [Nokogiri::XML::Element] The same element.
      #
      def self.drop_placeholder_namespaces(root)
        placeholders = root.namespace_definitions
        root.traverse do |node|
          node.namespace = nil if placeholders.include?(node.namespace)
          next unless node.element?

          drop_attribute_namespaces node, placeholders
        end
        root
      end
      private_class_method :drop_placeholder_namespaces

      #
      # Un-prefix the placeholder attributes of one element.
      #
      # Un-prefixing renames the attribute, so it can collide: an element
      # carrying both target and xlink:target would keep two attributes
      # called target, and Nokogiri rejects the result with "Attribute
      # target redefined" -- the unparseable output this whole path
      # exists to prevent. Drop the prefixed one instead.
      #
      # @param [Nokogiri::XML::Element] node The element.
      # @param [Array<Nokogiri::XML::Namespace>] placeholders The
      #   wrapper's own declarations.
      #
      # @return [void]
      #
      def self.drop_attribute_namespaces(node, placeholders)
        node.attribute_nodes.each do |attr|
          next unless placeholders.include?(attr.namespace)

          if plain_attribute?(node, attr.name) then attr.unlink
          else attr.namespace = nil
          end
        end
      end
      private_class_method :drop_attribute_namespaces

      #
      # Does the element already carry this attribute without a prefix?
      #
      # Nokogiri's Node#attribute matches on the name alone, so it finds
      # the prefixed attribute itself and every un-prefixing would look
      # like a collision. Match on the namespace as well.
      #
      # @param [Nokogiri::XML::Element] node The element.
      # @param [String] name The un-prefixed attribute name.
      #
      # @return [Boolean] Whether the element carries it.
      #
      def self.plain_attribute?(node, name)
        node.attribute_nodes.any? { |a| a.namespace.nil? && a.name == name }
      end
      private_class_method :plain_attribute?

      def self.sanitizable?(content)
        content.is_a?(::String) && !content.empty? && content.match?(TAG_RX)
      end
      private_class_method :sanitizable?

      def self.sanitize_children(node)
        node.children.to_a.each do |child|
          next unless child.element?

          child.name = RENAME[child.name] if RENAME.key?(child.name)
          next if OPAQUE.include?(child.name)

          sanitize_children(child)
          child.replace(child.children) unless ALLOWED.include?(child.name)
        end
      end
      private_class_method :sanitize_children
    end
  end
end
