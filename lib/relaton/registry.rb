require 'singleton'

class Error < StandardError
end

module Relaton
  class Registry
    include Singleton

    attr_reader :processors

    def initialize
      @processors = {}
    end

    def register processor
      raise Error unless processor < :: Relaton::Processor
      p = processor.new
      puts "[relaton] processor \"#{p.short}\" registered"
      @processors[p.short] = p
    end

    def find_processor(short)
      @processors[short.to_sym]
    end

    def supported_processors
      @processors.keys
    end

    def processors
      @processors
    end
  end
end

