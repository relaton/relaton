require "singleton"
require_relative "../core/request_error"

module Relaton
  class Db
    class Registry
      SUPPORTED_GEMS = %w[
        relaton/gb relaton/iec relaton/ietf relaton/iso
        relaton/itu relaton/nist relaton/ogc relaton/calconnect
        relaton/omg relaton/un relaton/w3c relaton/ieee
        relaton/iho relaton/bipm relaton/ecma relaton/cie
        relaton/bsi relaton/cen relaton/iana relaton/3gpp
        relaton/oasis relaton/doi relaton/jis relaton/xsf
        relaton/ccsds relaton/etsi relaton/isbn relaton/plateau
        relaton/oiml relaton/jcgm relaton/easc relaton/gost relaton/adobe
        relaton/iala
      ].freeze

      include Singleton

      attr_reader :processors

      def initialize
        @processors = {}
        register_gems
      end

      def register_gems
        SUPPORTED_GEMS.each do |b|
          # Load ONLY the lightweight processor file; its heavy flavor code is
          # lazy-required inside the processor's methods. This keeps
          # `require "relaton"` from eagerly loading every flavor at start.
          require "#{b}/processor"
          register Kernel.const_get "#{gem_to_module_path(b)}::Processor"
        rescue LoadError => e
          Util.error "backend #{b} not present\n" \
                     "#{e.message}\n#{e.backtrace.join "\n"}"
        end
      end

      def register(processor)
        raise Error unless processor < Core::Processor

        p = processor.new
        return if processors[p.short]

        Util.debug("processor \"#{p.short}\" registered")
        processors[p.short] = p
      end

      def find_processor(short)
        processors[short.to_sym]
      end

      # @return [Array<Symbol>]
      def supported_processors
        processors.keys
      end

      #
      # Search a rpocessos by dataset name
      #
      # @param [String] dataset
      #
      # @return [Relaton::Core::Processor, nil]
      #
      def find_processor_by_dataset(dataset)
        processors.values.detect { |p| p.datasets&.include? dataset }
      end

      #
      # Find processor by type
      #
      # @param type [String]
      # @return [Relaton::Core::Processor]
      def by_type(type)
        processors.values.detect { |v| v.prefix == type&.upcase }
      end

      def [](stdclass)
        processors[stdclass]
      end

      #
      # Find processor by reference or prefix
      #
      # @param [String] ref reference or prefix
      #
      # @return [Relaton::Core::Processor] processor
      #
      def processor_by_ref(ref)
        processors[class_by_ref(ref)]
      end

      #
      # The processor whose pubid class the identifier belongs to. Only the
      # generic `Pubid::AllPartsIdentifier`, which belongs to no flavor, is
      # matched through the document it wraps (`#root`). Any other identifier
      # is matched by its own class: the `#root` of an adoption is the adopted
      # document, so `CEN ISO/TS 21003-7` would otherwise be filed as ISO.
      #
      # @param pubid [Pubid::Identifier]
      # @return [Relaton::Core::Processor, nil]
      #
      def processor_by_pubid(pubid)
        generic = pubid.instance_of?(::Pubid::AllPartsIdentifier)
        id = generic ? pubid.root : pubid
        processors.values.detect do |processor|
          klass = processor.pubid_class
          klass && id.is_a?(klass)
        end
      end

      #
      # Route a reference to its flavor (relaton#205).
      #
      # 1. The reference is parsed with pubid. Only the parsing flavor's own
      #    **exact** parse counts (#exact_parse): `Pubid.parse` falls back to a
      #    partial parse by any flavor (`ATN5014` as `IEC ATN5014`), and a
      #    permissive grammar reads another publisher's string exactly
      #    (`ISO REF` as IEC).
      # 2. The parse routes by class ancestry (#processor_by_pubid), so the
      #    registration order does not matter.
      # 3. A co-published identifier routes to the co-publisher its printed
      #    form names first (`ISO/IEC …` → ISO, `IEC/ISO …` → IEC). This is
      #    relaton's routing policy (#205): there is no canonical form of the
      #    identifier, pubid does not route records (pubid#469), and
      #    `Pubid.parse` tries the owners of a joint prefix in alphabetical
      #    order.
      # 4. Otherwise the prefix regex (#class_by_ref) routes: a combined
      #    reference, the `PREFIX(code)` wrapper, a spelling a flavor
      #    normalizes, a flavor's free text.
      #
      # @param reference [String]
      # @return [Array(Symbol, Pubid::Identifier)] the standard class, and the
      #   parsed pubid when it is that flavor's own exact parse (else nil)
      # @raise [Relaton::UnknownReferenceError] no flavor recognizes it
      #
      def route(reference) # rubocop:disable Metrics/CyclomaticComplexity
        parsed = exact_parse reference
        stdclass = parsed && class_by_parsed(parsed, reference)
        parsed = nil unless stdclass
        lead = joint_lead reference
        return [lead, stdclass == lead ? parsed : nil] if lead
        return [stdclass, parsed] if stdclass

        stdclass = class_by_ref(reference)
        raise UnknownReferenceError, reference unless stdclass

        [stdclass, nil]
      end

      # Find processor by refernce or prefix
      #
      # @param ref [String] reference or prefix
      #
      # @return [Symbol, nil] standard class name
      #
      def class_by_ref(ref)
        ref = Regexp.last_match(1) if ref =~ /^\w+\((.*)\)$/
        @processors.each do |class_name, processor|
          return class_name if /^(urn:)?#{processor.prefix}\b/i.match?(ref) ||
            processor.defaultprefix.match(ref)
        end
        Util.info "`#{ref}` does not have a recognised prefix", key: ref
        nil
      end

      #
      # Global prefix register (relaton-db#103): all processors that own the
      # given global prefix, matched case-insensitively and exactly (unlike
      # #class_by_ref, which matches a prefix at the start of a full reference).
      # Ordered by registration order (SUPPORTED_GEMS), so results are
      # deterministic. Lazy: never dereferences a flavor constant.
      #
      # @param prefix [String]
      # @return [Array<Relaton::Core::Processor>]
      #
      def processors_by_prefix(prefix)
        key = prefix.to_s.strip.upcase
        processors.values.select do |processor|
          processor.prefixes.any? { |pref| pref.upcase == key }
        end
      end

      #
      # Flavor modules (e.g. Relaton::Iso) that own the given global prefix.
      # NOTE: dereferencing the returned module forces that flavor's lazy load.
      # Callers that must stay lazy should use #processors_by_prefix instead.
      #
      # @param prefix [String]
      # @return [Array<Module>]
      #
      def flavors_by_prefix(prefix)
        processors_by_prefix(prefix).map { |processor| flavor_module(processor) }
      end

      #
      # The flavor that serves a publisher's catalog: the processor whose own
      # prefix is the publisher (`IEC` → `:relaton_iec`). Nil for a publisher
      # no flavor serves (`ASTM`). Used for a co-publisher (relaton#205).
      #
      # @param publisher [String]
      # @return [Symbol, nil] the standard class
      #
      def class_by_publisher(publisher)
        processors_by_prefix(publisher)
          .detect { |processor| processor.prefix.casecmp?(publisher) }&.short
      end

      private

      # The reference parsed by pubid, when the parse renders the reference
      # back (pubid's round-trip test). pubid itself is loaded here, not at
      # registration. `Pubid.parse` raises a plain ArgumentError for a URN no
      # flavor owns (`urn:foo:bar`): that is no parse either.
      #
      # @param reference [String]
      # @return [Pubid::Identifier, nil]
      def exact_parse(reference)
        require "pubid"
        parsed = ::Pubid.parse reference
        parsed if parsed.to_s == reference
      rescue ArgumentError, ::Pubid::Errors::Error, Parslet::ParseFailed
        nil
      end

      # Whether the flavor of +pubid+ owns a prefix +reference+ starts with.
      def claims?(pubid, reference)
        flavor = ::Pubid.const_get pubid.class.name.split("::")[1]
        return false unless flavor.respond_to?(:prefixes)

        flavor.prefixes.any? { |pref| prefix_of?(pref, reference) }
      end

      # A prefix matches when the reference ends there or goes on with a
      # separator, or when the prefix itself ends with one (`doi:10.…`).
      def prefix_of?(prefix, reference)
        return false unless reference.start_with?(prefix)

        rest = reference[prefix.length]
        rest.nil? || !alnum?(rest) || !alnum?(prefix[-1])
      end

      def alnum?(char)
        char.match?(/[[:alnum:]]/)
      end

      # The flavor of an exact parse, when the parse is that flavor's own: the
      # flavor claims the reference by one of its prefixes, or its identifiers
      # print without one (Core::Processor#bare_identifiers?). A permissive
      # grammar reads other publishers' strings exactly (`ISO REF` as IEC,
      # `ABC 123456` as GB, a bare DOI as UN), but it does not claim them.
      #
      # @param pubid [Pubid::Identifier]
      # @param reference [String]
      # @return [Symbol, nil] the standard class
      def class_by_parsed(pubid, reference)
        processor = processor_by_pubid(pubid) or return
        return unless processor.bare_identifiers? || claims?(pubid, reference)

        processor.short
      end

      # The co-publisher that a joint prefix names first (`ISO/IEC 27001` →
      # ISO). Nil unless the reference starts with a prefix several flavors
      # own.
      #
      # @param reference [String]
      # @return [Symbol, nil] the standard class
      def joint_lead(reference)
        prefix = joint_prefixes.detect do |pref|
          reference == pref || reference.start_with?("#{pref} ")
        end
        return unless prefix

        class_by_publisher prefix.split("/").first
      end

      # Prefixes that more than one flavor owns (`ISO/IEC`, `ISO/IEC/IEEE`),
      # longest first.
      #
      # @return [Array<String>]
      def joint_prefixes
        @joint_prefixes ||= processors.values.flat_map(&:prefixes).uniq
          .select { |pref| pref.include?("/") && joint?(pref) }
          .sort_by { |pref| -pref.size }
      end

      def joint?(prefix)
        processors_by_prefix(prefix).size > 1
      end

      # The flavor namespace for a processor: the module enclosing its class.
      # Relaton::Iso::Processor -> Relaton::Iso. Derived from the class name so
      # there's no @short string-munging and no 3gpp special case.
      #
      # @param processor [Relaton::Core::Processor]
      # @return [Module]
      def flavor_module(processor)
        Object.const_get processor.class.name.split("::")[0..-2].join("::")
      end

      def gem_to_module_path(gem_name)
        gem_name.split("/").map do |part|
          part.capitalize.sub("3gpp", "ThreeGpp")
        end.join("::")
      end
    end
  end
end
