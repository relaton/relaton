module Relaton
  class Processor
    # @rerurn [Symbol]
    attr_reader :short

    # @return [String]
    attr_reader :prefix, :idtype

    # @return [Regexp]
    attr_reader :defaultprefix

    # @return [Array<String>]
    attr_reader :datasets

    def initialize
      raise "This is an abstract class!"
    end

    def get(_code, _date, _opts)
      raise "This is an abstract class!"
    end

    def fetch_data(_source, _opts)
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
