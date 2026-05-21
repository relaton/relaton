require "weakref"

module Relaton
  module Core
    class Hit
      # @return [RelatonBib::HitCollection]
      attr_accessor :hit_collection

      # @return [Array<Hash>]
      attr_reader :hit

      # @param hit [Hash]
      # @param hit_collection [RelatonBib::HitCollection]
      def initialize(hit, hit_collection = nil)
        @hit            = hit
        @hit_collection = WeakRef.new hit_collection if hit_collection
      end

      # @return [String]
      def to_s
        inspect
      end

      # @return [String]
      def inspect
        "<#{self.class}:#{format('%<id>#.14x', id: object_id << 1)} " \
          "@reference=\"#{@hit_collection&.ref}\" " \
          "@fetched=\"#{fetched?}\" " \
          "@docidentifier=\"#{@hit[:code]}\">"
      end

      # @return [RelatonBib::ItemData]
      def item
        raise "Not implemented"
      end

      def fetched?
        !@item.nil?
      end

      # @param opts [Hash]
      # @option opts [Boolean] :bibdata
      # @return [String] XML
      def to_xml(**opts)
        item.to_xml(**opts)
      end
    end
  end
end
