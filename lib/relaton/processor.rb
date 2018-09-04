module Relaton
  class Processor

    attr_reader :short
    attr_reader :prefix
    attr_reader :defaultprefix

    def initialize
      raise "This is an abstract class!"
    end

    def get(code, date, opts)
      raise "This is an abstract class!"
    end
  end
end

