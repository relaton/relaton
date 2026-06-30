require "forwardable"
require "nokogiri"
require "weakref"
require_relative "hit"

module Relaton
  module Core
    class HitCollection
      extend Forwardable

      def_delegators :@array, :<<, :[], :first, :empty?, :any?, :size, :each, :each_slice, :reduce, :map

      # @return [TrueClass, FalseClass]
      attr_reader :fetched

      # @return [String]
      attr_reader :ref

      # @return [String]
      attr_reader :year

      #
      # @param ref [String, Pubid] reference to search
      # @param year [String, nil] year of publication
      #
      def initialize(ref, year = nil)
        @array = []
        @ref = ref
        @year = year
        @fetched = false
      end

      #
      # Fetches hits from the data source
      #
      # @return [self] self object
      #
      def fetch
        workers = WorkersPool.new 4
        workers.worker(&:item)
        each do |hit|
          workers << hit
        end
        workers.end
        workers.result
        @fetched = true
        self
      end

      #
      # Renders the collection as XML
      #
      # @param opts [Hash] options
      # @option opts [Nokogiri::XML::Builder] :builder XML builder
      # @option opts [Boolean] :bibdata render bibdata if true
      # @option opts [String, Symbol] :lang language
      #
      # @return [String] XML representation of the collection
      #
      def to_xml(**opts)
        builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
          xml.documents do
            @array.each do |hit|
              xml << hit.to_xml(**opts)
            end
          end
        end
        builder.to_xml
      end

      #
      # Selects matching hits and returns a new collection
      #
      # @param [Proc] &block proc to select hits
      #
      # @return [RelatonBib::HitCollection] new hit collection
      #
      def select!(&block)
        @array.select!(&block)
        self
      end

      def select(&block)
        array = @array.select(&block)
        self.class.new(@ref, @year).tap do |hc|
          new_array = array.map do |hit|
            hit.dup.tap { |h| h.hit_collection = WeakRef.new(hc) }
          end
          hc.instance_variable_set(:@array, new_array)
          hc.instance_variable_set(:@fetched, @fetched)
        end
      end

      def reduce!(sum, &block)
        @array = @array.reduce sum, &block
        self
      end

      #
      # Returns String representation of the collection
      #
      # @return [String] String representation of the collection
      #
      def to_s
        inspect
      end

      #
      # Returns String representation of the collection
      #
      # @return [String] String representation of the collection
      #
      def inspect
        "<#{self.class}:#{format('%#.14x', object_id << 1)} @ref=#{@ref} @fetched=#{@fetched}>"
      end
    end
  end
end
