module Relaton
  class Processor
    attr_reader :short
    attr_reader :prefix
    attr_reader :defaultprefix
    attr_reader :idtype

    def initialize
      raise "This is an abstract class!"
    end

    def get(_code, _date, _opts)
      raise "This is an abstract class!"
    end

    def from_xml(_xml)
      raise "This is an abstract class!"
    end

    def hash_to_bib(_hash)
      raise "This is an abstract class!"
    end

    def grammar_hash
      raise "This is an abstract class!"
    end

    # Retuns default number of workers. Should be overraded by childred classes if need.
    #
    # @return [Integer] nuber of wokrers
    def threads
      10
    end
  end
end
