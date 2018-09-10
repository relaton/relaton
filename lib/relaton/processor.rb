module Relaton
  class Processor

    attr_reader :short
    attr_reader :prefix
    attr_reader :defaultprefix
    attr_reader :idtype

    def initialize
      raise "This is an abstract class!"
    end

    def get(code, date, opts)
      raise "This is an abstract class!"
    end
  end
end

