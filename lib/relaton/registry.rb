require "singleton"

class Error < StandardError
end

module Relaton
  class Registry
    SUPPORTED_GEMS = %w[
      relaton_gb relaton_iec relaton_ietf relaton_iso relaton_itu relaton_nist
      relaton_ogc relaton_calconnect relaton_omg relaton_un relaton_w3c
      relaton_ieee relaton_iho relaton_bipm relaton_ecma relaton_cie relaton_bsi
      relaton_cen relaton_iana relaton_3gpp relaton_oasis relaton_doi relaton_jis
      relaton_xsf relaton_ccsds
    ].freeze

    include Singleton

    attr_reader :processors

    def initialize
      @processors = {}
      register_gems
    end

    def register_gems
      # Util.log("[relaton] Info: detecting backends:", :info)

      SUPPORTED_GEMS.each do |b|
        require b
        require "#{b}/processor"
        register Kernel.const_get "#{camel_case(b)}::Processor"
      rescue LoadError => e
        Util.log("[relaton] Error: backend #{b} not present", :error)
        Util.log("[relaton] Error: #{e.message}", :error)
        Util.log("[relaton] Error: #{e.backtrace.join "\n"}", :error)
      end
    end

    def register(processor)
      raise Error unless processor < ::Relaton::Processor

      p = processor.new
      return if processors[p.short]

      Util.log("[relaton] processor \"#{p.short}\" registered", :debug)
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
    # @return [Relaton::Processor, nil]
    #
    def find_processor_by_dataset(dataset)
      processors.values.detect { |p| p.datasets&.include? dataset }
    end

    #
    # Find processor by type
    #
    # @param type [String]
    # @return [RelatonIso::Processor, RelatonIec::Processor,
    #   RelatonNist::Processor, RelatonIetf::Processot, RelatonItu::Processor,
    #   RelatonGb::Processor, RelatonOgc::Processor,
    #   RelatonCalconnect::Processor]
    def by_type(type)
      processors.values.detect { |v| v.prefix == type&.upcase }
    end

    #
    # Find processor by reference or prefix
    #
    # @param [String] ref reference or prefix
    #
    # @return [Relaton::Processor] processor
    #
    def processor_by_ref(ref)
      @processors[class_by_ref(ref)]
    end

    #
    # Find processor by refernce or prefix
    #
    # @param ref [String] reference or prefix
    #
    # @return [Symbol, nil] standard class name
    #
    def class_by_ref(ref)
      @processors.each do |class_name, processor|
        return class_name if /^(urn:)?#{processor.prefix}(?!\w)/i.match?(ref) ||
          processor.defaultprefix.match(ref)
      end
      Util.log <<~WARN, :info
        [relaton] #{ref} does not have a recognised prefix
      WARN
    end

    private

    def camel_case(gem_name)
      gem_name.split("_").map(&:capitalize).join
    end
  end
end
