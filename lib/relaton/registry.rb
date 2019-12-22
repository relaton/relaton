require "singleton"

class Error < StandardError
end

module Relaton
  class Registry
    SUPPORTED_GEMS = %w[
      relaton_gb relaton_iec relaton_ietf relaton_iso relaton_itu relaton_nist
      relaton_ogc relaton_calconnect
    ].freeze

    include Singleton

    attr_reader :processors

    def initialize
      @processors = {}
      register_gems
    end

    def register_gems
      puts "[relaton] Info: detecting backends:"
      SUPPORTED_GEMS.each do |b|
        begin
          require b
          require "#{b}/processor"
          register Kernel.const_get "#{camel_case(b)}::Processor"
        rescue LoadError
          puts "[relaton] Error: backend #{b} not present"
        end
      end
    end

    def register(processor)
      raise Error unless processor < ::Relaton::Processor

      p = processor.new
      return if processors[p.short]

      puts "[relaton] processor \"#{p.short}\" registered"
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
    # Find processor by type
    #
    # @param type [String]
    # @return [RelatonIso::Processor, RelatonIec::Processor, RelatonNist::Processor,
    #   RelatonIetf::Processot, RelatonItu::Processor, RelatonGb::Processor,
    #   RelatonOgc::Processor, RelatonCalconnect::Processor]
    def by_type(type)
      processors.values.detect { |v| v.prefix == type&.upcase }
    end

    private

    def camel_case(gem_name)
      gem_name.split("_").map(&:capitalize).join
    end
  end
end
